import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// アプリ全体で使用するカスタム画像キャッシュマネージャー。
///
/// デフォルトの [DefaultCacheManager] は有効期限30日・サイズ制限なしで
/// 大量のキャッシュが蓄積されるため、以下の設定でキャッシュ量を抑制する。
/// - 有効期限: 7日
/// - 最大エントリ数: 400
class AppCacheManager extends CacheManager with ImageCacheManager {
  static const _key = 'coerieImageCache';

  static final AppCacheManager _instance = AppCacheManager._();

  factory AppCacheManager() => _instance;

  AppCacheManager._()
    : super(
        Config(
          _key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 400,
        ),
      );

  /// キャッシュの合計サイズをバイト単位で返す。
  ///
  /// Android の getCacheDir() 相当である [getTemporaryDirectory] 全体を集計する。
  /// これにより、OS の「アプリ設定 > キャッシュ」と同じ値が得られる。
  static Future<int> getCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      return await _calcDirSize(tempDir);
    } catch (_) {
      return 0;
    }
  }

  /// キャッシュを全て削除する。
  ///
  /// flutter_cache_manager の DB エントリを先に整理してから、
  /// [getTemporaryDirectory] 配下のファイルをすべて直接削除する。
  /// これにより OS の「キャッシュを消去」と同等の効果が得られる。
  static Future<void> clearAllCache() async {
    // flutter_cache_manager の内部 DB を先にクリア
    try {
      await AppCacheManager().emptyCache();
    } catch (_) {}
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}

    // 一時ディレクトリ配下のファイル・サブディレクトリを直接削除
    try {
      final tempDir = await getTemporaryDirectory();
      await for (final entity in tempDir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<int> _calcDirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (_) {}
    return size;
  }
}
