import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import 'shared_preferences_provider.dart';

/// アカウントIDごとにデフォルト投稿公開範囲を保存・管理するプロバイダー
final accountVisibilityProvider =
    StateNotifierProvider.family<AccountVisibilityNotifier, String, String>((
      ref,
      accountId,
    ) {
      final prefs = ref.read(sharedPreferencesProvider);
      return AccountVisibilityNotifier(accountId, prefs);
    });

class AccountVisibilityNotifier extends StateNotifier<String> {
  final String accountId;
  final SharedPreferences _prefs;

  AccountVisibilityNotifier(this.accountId, this._prefs)
    : super(
        _prefs.getString('visibility_$accountId') ??
            AppConstants.visibilityPublic,
      );

  static String _prefsKey(String accountId) => 'visibility_$accountId';

  Future<void> setVisibility(String visibility) async {
    state = visibility;
    if (accountId.isEmpty) return;
    await _prefs.setString(_prefsKey(accountId), visibility);
  }
}
