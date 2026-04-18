package com.coerie.coerie

import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
	private val CHANNEL = "coerie/share"
	private var latestText: String? = null
	private var latestFiles: ArrayList<String>? = null
	private var methodChannel: MethodChannel? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
		methodChannel?.setMethodCallHandler { call, result ->
			if (call.method == "getInitialSharedData") {
				val map: MutableMap<String, Any?> = HashMap()
				map["text"] = latestText
				map["files"] = latestFiles
				result.success(map)
			} else {
				result.notImplemented()
			}
		}
		handleIntent(intent, false)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleIntent(intent, true)
	}

	/**
	 * content:// URI を cacheDir 配下の一時ファイルにコピーし、
	 * Flutter から File() で読み書きできる絶対パスを返す。
	 */
	private fun resolveToTempFile(uri: Uri): String? {
		if (uri.scheme == "file") return uri.path
		return try {
			val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
			val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "tmp"
			val dir = File(cacheDir, "shared_media").also { it.mkdirs() }
			val tmp = File.createTempFile("share_", ".$ext", dir)
			contentResolver.openInputStream(uri)?.use { input ->
				tmp.outputStream().use { output -> input.copyTo(output) }
			}
			tmp.absolutePath
		} catch (e: Exception) {
			null
		}
	}

	private fun handleIntent(intent: Intent, sendToDart: Boolean) {
		val action = intent.action
		val type = intent.type
		if (Intent.ACTION_SEND == action && type != null) {
			if (type.startsWith("text")) {
				val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
				latestText = sharedText
				latestFiles = null
				if (sendToDart) {
					methodChannel?.invokeMethod("onSharedText", sharedText)
				}
			} else if (type.startsWith("image") || type.startsWith("video") || type.startsWith("audio")) {
				val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
				if (uri != null) {
					val path = resolveToTempFile(uri)
					if (path != null) {
						latestFiles = arrayListOf(path)
						latestText = null
						if (sendToDart) methodChannel?.invokeMethod("onSharedFiles", latestFiles)
					}
				}
			}
		} else if (Intent.ACTION_SEND_MULTIPLE == action) {
			val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
			if (uris != null && uris.isNotEmpty()) {
				val paths = ArrayList<String>()
				for (u in uris) {
					val path = resolveToTempFile(u)
					if (path != null) paths.add(path)
				}
				if (paths.isNotEmpty()) {
					latestFiles = paths
					latestText = null
					if (sendToDart) methodChannel?.invokeMethod("onSharedFiles", latestFiles)
				}
			}
		}
	}
}
