import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'account_provider.dart';
import 'misskey_api_provider.dart';
import 'shared_preferences_provider.dart';

/// アクティブアカウントの「フォロー承認制」設定を保持するプロバイダー。
///
/// - 起動時は SharedPreferences のキャッシュ値を即座に返す（フラッシュ防止）
/// - その後バックグラウンドで API から最新値を取得してキャッシュを更新する
/// - アカウント切り替え時は新しいアカウントのキャッシュ値を即座に適用し、再取得する
class IsLockedNotifier extends StateNotifier<bool> {
  final Ref _ref;

  IsLockedNotifier(this._ref) : super(false) {
    _init();
    _ref.listen<String?>(activeAccountProvider.select((a) => a?.id), (
      prev,
      next,
    ) {
      if (next != null && prev != next) {
        _applyCache(next);
        _fetchFromApi();
      }
    });
  }

  /// SharedPreferences からキャッシュ値を同期的に適用する
  void _applyCache(String accountId) {
    final prefs = _ref.read(sharedPreferencesProvider);
    final cached = prefs.getBool('isLocked_$accountId');
    if (cached != null) {
      state = cached;
    }
  }

  Future<void> _init() async {
    final accountId = _ref.read(activeAccountProvider)?.id ?? '';
    if (accountId.isNotEmpty) {
      _applyCache(accountId); // 即座にキャッシュを適用
    }
    await _fetchFromApi(); // バックグラウンドで最新値を取得
  }

  Future<void> _fetchFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final user = await api.getMe();
      if (!mounted) return;
      state = user.isLocked;
      // キャッシュを更新
      final accountId = _ref.read(activeAccountProvider)?.id ?? '';
      if (accountId.isNotEmpty) {
        await _ref
            .read(sharedPreferencesProvider)
            .setBool('isLocked_$accountId', user.isLocked);
      }
    } catch (_) {
      // ネットワークエラー等はキャッシュ値のまま維持
    }
  }
}

/// アプリ起動時に早期初期化するため autoDispose を付けない。
final isLockedProvider = StateNotifierProvider<IsLockedNotifier, bool>(
  (ref) => IsLockedNotifier(ref),
);
