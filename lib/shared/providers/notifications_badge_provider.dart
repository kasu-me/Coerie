import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streaming/streaming_service.dart';
import '../../data/models/notification_model.dart';
import '../../data/remote/misskey_api.dart';
import 'last_seen_badge_notifier.dart';

/// ホーム画面のアイコンに付ける「未読通知」バッジの状態。
///
/// サーバーの既読状態（`isRead`）とローカルの lastSeen の両方を見る。
class _NotificationsBadgeNotifier
    extends LastSeenBadgeNotifier<NotificationModel> {
  _NotificationsBadgeNotifier(super.ref, super.accountId);

  @override
  String get prefsKeyPrefix => 'notifications_last_seen';

  @override
  Future<List<NotificationModel>> fetchItems(MisskeyApi api) =>
      api.getNotifications(limit: 50);

  @override
  DateTime createdAtOf(NotificationModel item) => item.createdAt;

  @override
  bool isUnread(NotificationModel item) => !item.isRead;

  @override
  Stream<NotificationModel> streamOf(StreamingService streaming) =>
      streaming.notificationStream;

  @override
  Future<void> onClear(MisskeyApi api) => api.markNotificationsRead();
}

final notificationsBadgeProvider = StateNotifierProvider.autoDispose
    .family<_NotificationsBadgeNotifier, int, String>((ref, accountId) {
      return _NotificationsBadgeNotifier(ref, accountId);
    });
