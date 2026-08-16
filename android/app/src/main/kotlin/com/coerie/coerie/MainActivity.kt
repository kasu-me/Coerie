package com.coerie.coerie

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
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

	override fun onWindowFocusChanged(hasFocus: Boolean) {
		super.onWindowFocusChanged(hasFocus)
		// ImeSyncDeferringInsetsCallback（後述）は API 30+ でのみインストールされるため
		// 本事象も API 30+ でしか起きない。isVisible(ime()) も API 30+ 依存。
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
		cancelImeInsetsRecovery()
		if (hasFocus) startImeInsetsRecovery()
	}

	override fun onDestroy() {
		cancelImeInsetsRecovery()
		super.onDestroy()
	}

	private val imeInsetsRecoveryHandler = Handler(Looper.getMainLooper())
	private var imeInsetsRecoveryRunnable: Runnable? = null

	/**
	 * IME を表示したまま他アプリへ切り替え、そのアプリでも IME を出してから戻ると、
	 * キーボードが無いのに同じ高さの空白が残る事象への復旧処理（Pixel 6a / Gboard で報告）。
	 *
	 * 根本原因は Flutter エンジンの ImeSyncDeferringInsetsCallback（API 30+）にある。
	 * WindowInsetsAnimation.Callback#onPrepare で animating フラグが立ち、これを下ろす
	 * 経路は onEnd ただ一つで、アニメーション中断やフォーカス喪失時の復旧処理が存在しない
	 * （Flutter 3.41.6 および master のソースで確認済みの上流バグ）。アプリ切替で IME の
	 * ハンドオフ/非表示アニメーションが onEnd を伴わず中断されるとフラグが固着し、以後の
	 * インセット変化はすべて WindowInsets.CONSUMED で握り潰されて FlutterView に届かない。
	 * テキスト欄を再タップすると新しい IME アニメーションが正常に完走して onEnd で
	 * フラグが戻るため解消する——という報告者の観察とも一致する。
	 *
	 * フォーカス復帰直後の一回きりの再適用では直らなかったため、複数回リトライする。
	 * 一回きりで不十分な理由：
	 * - 復帰直後は rootWindowInsets 自体がまだ復帰前の古い値（IME 表示中）のことがあり、
	 *   その時点で再適用しても空白を再適用するだけになる
	 * - フォーカス復帰の後にシステムが IME の後始末アニメーションをもう一度走らせ、
	 *   （それも onEnd なしで中断されて）再度固着する「再汚染」が起きうる
	 */
	private fun startImeInsetsRecovery() {
		// 1 秒強の範囲で間隔を空けて数回試す。システム側のインセット確定と
		// 後始末アニメーションの中断がいつ起きても拾えるようにするための値で、
		// 正常時は現在値の再適用（no-op 相当）になるため副作用はない。
		val delays = longArrayOf(0, 100, 250, 500, 1000)
		var index = 0
		val runnable = object : Runnable {
			override fun run() {
				recoverImeInsets()
				index++
				if (index < delays.size) {
					imeInsetsRecoveryHandler.postDelayed(this, delays[index] - delays[index - 1])
				}
			}
		}
		imeInsetsRecoveryRunnable = runnable
		imeInsetsRecoveryHandler.post(runnable)
	}

	private fun cancelImeInsetsRecovery() {
		imeInsetsRecoveryRunnable?.let { imeInsetsRecoveryHandler.removeCallbacks(it) }
		imeInsetsRecoveryRunnable = null
	}

	private fun recoverImeInsets() {
		val flutterView = findFlutterView(window.decorView) ?: return
		val insets = flutterView.rootWindowInsets ?: return
		// IME が本当に表示中（リトライ期間中にユーザーがテキスト欄をタップした場合など）は
		// 触らない。表示アニメーションの完走（onEnd）でエンジン側の状態も正常に戻るし、
		// アニメーション途中に介入するとコンテンツが先にジャンプする見た目の乱れが出る。
		if (insets.isVisible(WindowInsets.Type.ime())) return
		resetImeSyncCallbackState(flutterView)
		// リスナーを経由しない View#onApplyWindowInsets の直接呼び出しで握り潰しを迂回して
		// 現在値を即時反映する。エンジン自身もアニメーション中のインセット反映に同じ手法を
		// 使っている。requestApplyInsets() では同じリスナーを通るため解消しない。
		// リフレクションが失敗した場合の表示復旧のフォールバックも兼ねる。
		flutterView.onApplyWindowInsets(insets)
	}

	/**
	 * 固着した animating / needsSave フラグをリフレクションで強制リセットする。
	 * エンジンに公開 API が無く、フラグを下ろさない限り「以後のインセット変化が
	 * FlutterView に届かない」状態自体は解消できないため、やむを得ず内部に手を入れる。
	 * Flutter アップグレードでフィールド構成が変わった場合は catch で無害に無効化され、
	 * 呼び出し元の直接適用（表示の復旧のみ）が引き続き機能する。
	 * release ビルドは minify 無効のため難読化によるフィールド名変化の心配はない。
	 */
	private fun resetImeSyncCallbackState(flutterView: FlutterView) {
		try {
			val pluginField = FlutterView::class.java.getDeclaredField("textInputPlugin")
			pluginField.isAccessible = true
			val textInputPlugin = pluginField.get(flutterView) ?: return
			val callbackField = textInputPlugin.javaClass.getDeclaredField("imeSyncCallback")
			callbackField.isAccessible = true
			val imeSyncCallback = callbackField.get(textInputPlugin) ?: return
			for (name in arrayOf("animating", "needsSave")) {
				val field = imeSyncCallback.javaClass.getDeclaredField(name)
				field.isAccessible = true
				field.setBoolean(imeSyncCallback, false)
			}
		} catch (_: Exception) {
			// フィールド構成の変化（エンジン更新）など。表示は直接適用側で復旧する
		}
	}

	private fun findFlutterView(view: View): FlutterView? {
		if (view is FlutterView) return view
		if (view is ViewGroup) {
			for (i in 0 until view.childCount) {
				findFlutterView(view.getChildAt(i))?.let { return it }
			}
		}
		return null
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
