package com.coerie.coerie

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
	private val CHANNEL = "coerie/share"
	private val DOWNLOAD_CHANNEL = "coerie/download_helper"
	private var latestText: String? = null
	private var latestFiles: ArrayList<String>? = null
	private var methodChannel: MethodChannel? = null
	private var downloadChannel: MethodChannel? = null

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

		downloadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
		downloadChannel?.setMethodCallHandler { call, result ->
			if (call.method == "saveToDownloads") {
				val filePath = call.argument<String>("filePath")
				val fileName = call.argument<String>("fileName")
				if (filePath == null || fileName == null) {
					result.error("INVALID_ARGS", "filePath and fileName are required", null)
					return@setMethodCallHandler
				}
				try {
					saveToDownloads(filePath, fileName)
					result.success(null)
				} catch (e: Exception) {
					result.error("SAVE_FAILED", e.message, null)
				}
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
	 * ファイルを公開 Downloads フォルダへ保存する。
	 * Android 10+ (API 29+): MediaStore.Downloads を使用（権限不要）
	 * Android 9 以下: WRITE_EXTERNAL_STORAGE 権限が必要
	 */
	@Suppress("DEPRECATION")
	private fun saveToDownloads(filePath: String, fileName: String) {
		val sourceFile = File(filePath)
		val ext = fileName.substringAfterLast('.', "").lowercase()
		val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
			?: "application/octet-stream"

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			val resolver = contentResolver
			val contentValues = ContentValues().apply {
				put(MediaStore.Downloads.DISPLAY_NAME, fileName)
				put(MediaStore.Downloads.MIME_TYPE, mimeType)
				put(MediaStore.Downloads.IS_PENDING, 1)
			}
			val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
				?: throw IOException("Failed to create Downloads URI for $fileName")
			resolver.openOutputStream(uri)?.use { out ->
				sourceFile.inputStream().use { it.copyTo(out) }
			}
			contentValues.clear()
			contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
			resolver.update(uri, contentValues, null, null)
		} else {
			val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
			downloadDir.mkdirs()
			sourceFile.copyTo(File(downloadDir, fileName), overwrite = true)
		}
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
