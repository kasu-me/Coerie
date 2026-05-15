import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// ファイルをダウンロードして Android の公開 Downloads フォルダへ保存するユーティリティ。
///
/// Android 10+ (API 29+): MediaStore.Downloads 経由で保存（権限不要）
/// Android 9 以下: 直接 DIRECTORY_DOWNLOADS へ書き込み（WRITE_EXTERNAL_STORAGE 権限が必要）
class DownloadHelper {
  static const _channel = MethodChannel('coerie/download_helper');

  /// [url] から [fileName] という名前でファイルをダウンロードし、
  /// Android の Downloads フォルダへ保存する。
  static Future<void> downloadToPublicDownloads({
    required String url,
    required String fileName,
    ProgressCallback? onReceiveProgress,
  }) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}${Platform.pathSeparator}$fileName';
    final tempFile = File(tempPath);
    try {
      await dio.download(url, tempPath, onReceiveProgress: onReceiveProgress);
      await _channel.invokeMethod<void>('saveToDownloads', {
        'filePath': tempPath,
        'fileName': fileName,
      });
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
