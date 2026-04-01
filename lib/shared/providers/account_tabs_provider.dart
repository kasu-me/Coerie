import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_settings_model.dart';
import 'shared_preferences_provider.dart';

/// アカウントIDごとにタブ設定を保存・管理するプロバイダー
final accountTabsProvider =
    StateNotifierProvider.family<
      AccountTabsNotifier,
      List<TabConfigModel>,
      String
    >((ref, accountId) {
      final prefs = ref.read(sharedPreferencesProvider);
      return AccountTabsNotifier(accountId, prefs);
    });

class AccountTabsNotifier extends StateNotifier<List<TabConfigModel>> {
  final String accountId;
  final SharedPreferences _prefs;

  AccountTabsNotifier(this.accountId, this._prefs)
    : super(_loadSync(accountId, _prefs));

  static List<TabConfigModel> _loadSync(
    String accountId,
    SharedPreferences prefs,
  ) {
    if (accountId.isEmpty) return const [];
    final jsonStr = prefs.getString('tabs_$accountId');
    if (jsonStr == null) return const [];
    try {
      return (jsonDecode(jsonStr) as List<dynamic>)
          .map((e) => TabConfigModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setTabs(List<TabConfigModel> tabs) async {
    // 常に新しいリストオブジェクトを生成してRiverpodに変更を確実に通知する
    state = List.unmodifiable(tabs);
    if (accountId.isEmpty) return;
    await _prefs.setString(
      'tabs_$accountId',
      jsonEncode(tabs.map((t) => t.toJson()).toList()),
    );
  }
}
