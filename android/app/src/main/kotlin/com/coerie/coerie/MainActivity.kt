package com.coerie.coerie

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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

	private fun handleIntent(intent: Intent, sendToDart: Boolean) {
		val action = intent.action
		val type = intent.type
		if (Intent.ACTION_SEND == action && type != null) {
			if (type.startsWith("text") || type == "text/plain") {
				val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
				latestText = sharedText
				if (sendToDart) {
					methodChannel?.invokeMethod("onSharedText", sharedText)
				}
			} else if (type.startsWith("image") || type.startsWith("video")) {
				val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
				if (uri != null) {
					val uriStr = uri.toString()
					latestFiles = arrayListOf(uriStr)
					if (sendToDart) methodChannel?.invokeMethod("onSharedFiles", latestFiles)
				}
			}
		} else if (Intent.ACTION_SEND_MULTIPLE == action) {
			val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
			if (uris != null && uris.isNotEmpty()) {
				latestFiles = ArrayList()
				for (u in uris) latestFiles?.add(u.toString())
				if (sendToDart) methodChannel?.invokeMethod("onSharedFiles", latestFiles)
			}
		}
	}
}
