import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/mention_history_entry.dart';
import '../../data/models/user_model.dart';
import 'shared_preferences_provider.dart';

/// アカウントごとのメンション履歴（新しい順）。family のキーはアカウントID。
///
/// サーバーが違えば同じユーザー名でも別人になるため、アカウント単位で分けている。
final mentionHistoryProvider =
    StateNotifierProvider.family<
      MentionHistoryNotifier,
      List<MentionHistoryEntry>,
      String
    >((ref, accountId) {
      return MentionHistoryNotifier(
        ref.read(sharedPreferencesProvider),
        accountId,
      );
    });

class MentionHistoryNotifier extends StateNotifier<List<MentionHistoryEntry>> {
  final SharedPreferences _prefs;
  final String _key;

  MentionHistoryNotifier(this._prefs, String accountId)
    : _key = _keyFor(accountId),
      super(_load(_prefs, _keyFor(accountId)));

  static String _keyFor(String accountId) =>
      '${AppConstants.mentionHistoryKeyPrefix}$accountId';

  static List<MentionHistoryEntry> _load(SharedPreferences prefs, String key) {
    final jsonStr = prefs.getString(key);
    if (jsonStr == null) return const [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map(
            (e) => MentionHistoryEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      // 壊れた履歴は補完の付加機能に過ぎないので、黙って捨てて空から作り直す
      return const [];
    }
  }

  /// [users] を履歴の先頭に積む。同一ユーザーは重複させず、新しい順に並べ替える。
  Future<void> record(Iterable<UserModel> users) async {
    if (users.isEmpty) return;
    // 挿入順を保つ Map で重複を潰す。既存エントリと同一ユーザーなら新しい情報
    // （表示名・アバターの変更）で上書きしつつ、位置は先頭に来る。
    final merged = <String, MentionHistoryEntry>{
      for (final user in users) user.id: MentionHistoryEntry.fromUser(user),
    };
    for (final entry in state) {
      merged.putIfAbsent(entry.userId, () => entry);
    }
    final next = merged.values
        .take(AppConstants.mentionHistoryLimit)
        .toList();
    state = next;
    await _prefs.setString(
      _key,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }
}
