import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/announcement_model.dart';
import '../../data/remote/misskey_api.dart';
import 'last_seen_badge_notifier.dart';

/// ホーム画面のアイコンに付ける「未読のお知らせ」バッジの状態。
///
/// 通知・DM と違い、サーバー側にも既読を書き戻す（`readAnnouncement`）。
/// ただし書き戻しが反映されるまでの間はローカルの [_locallyReadIds] で補う。
class _AnnouncementsBadgeNotifier
    extends LastSeenBadgeNotifier<AnnouncementModel> {
  /// 個別に既読にしたお知らせ。サーバーの既読状態が追いつくまでの繋ぎ。
  final Set<String> _locallyReadIds = {};

  _AnnouncementsBadgeNotifier(super.ref, super.accountId);

  @override
  String get prefsKeyPrefix => 'announcements_last_seen';

  @override
  Future<List<AnnouncementModel>> fetchItems(MisskeyApi api) =>
      api.getAnnouncements(limit: 50);

  @override
  DateTime createdAtOf(AnnouncementModel item) => item.createdAt;

  @override
  bool isUnread(AnnouncementModel item) =>
      !item.isRead && !_locallyReadIds.contains(item.id);

  /// すべてのお知らせをサーバー側でも既読にする。
  /// 大量にあると重いため、順に待って一度に流さない。
  @override
  Future<void> onClear(MisskeyApi api) async {
    final items = await api.getAnnouncements(limit: 50);
    for (final a in items) {
      try {
        await api.readAnnouncement(a.id);
      } catch (_) {
        // 1件失敗しても残りは既読にする
      }
    }
    // サーバー側に反映できたので、繋ぎのローカル既読は不要になる。
    _locallyReadIds.clear();
  }

  /// 1件だけ既読にする（詳細画面での操作）。バッジを1つ減らす。
  void markOneRead([String? announcementId]) {
    if (announcementId != null) _locallyReadIds.add(announcementId);
    if (state > 0) state = state - 1;
  }
}

final announcementsBadgeProvider = StateNotifierProvider.autoDispose
    .family<_AnnouncementsBadgeNotifier, int, String>((ref, accountId) {
      return _AnnouncementsBadgeNotifier(ref, accountId);
    });
