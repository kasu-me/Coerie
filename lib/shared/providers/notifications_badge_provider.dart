import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streaming/streaming_service.dart';
import 'misskey_api_provider.dart';
import 'shared_preferences_provider.dart';
import '../../data/models/notification_model.dart';

class _NotificationsBadgeNotifier extends StateNotifier<int> {
  final Ref _ref;
  final String _accountId;
  StreamSubscription<NotificationModel>? _streamSub;

  _NotificationsBadgeNotifier(this._ref, this._accountId) : super(0) {
    _init();
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _streamSub?.cancel();
      _streamSub = null;
      _subscribeStream();
    });
    // 自動再接続成功時に切断中の未読通知を取得する
    _ref.listen<AsyncValue<StreamingStatus>>(streamingStatusProvider, (
      prev,
      next,
    ) {
      if (prev?.valueOrNull == StreamingStatus.reconnecting &&
          next.valueOrNull == StreamingStatus.connected) {
        refreshFromApi();
      }
    });
  }

  Future<void> _init() async {
    await refreshFromApi();
    _subscribeStream();
  }

  /// API から通知を再取得してバッジ数を更新する。
  /// 主に WebSocket が切断されているときのフォールバックとして利用する。
  Future<void> refreshFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final lastSeenKey = 'notifications_last_seen_$_accountId';
      final lastSeenStr = prefs.getString(lastSeenKey);
      DateTime? lastSeen;
      if (lastSeenStr != null) {
        try {
          lastSeen = DateTime.parse(lastSeenStr);
        } catch (_) {}
      }

      final items = await api.getNotifications(limit: 50);
      final unread = items.where((n) {
        final serverUnread = !(n.isRead);
        final afterLastSeen = lastSeen == null || n.createdAt.isAfter(lastSeen);
        return serverUnread && afterLastSeen;
      }).length;
      state = unread;
    } catch (_) {
      // ignore errors
    }
  }

  void _subscribeStream() {
    final streaming = _ref.read(streamingServiceProvider);
    if (streaming == null) return;
    _streamSub = streaming.notificationStream.listen((notification) {
      // if notification is already marked read on server, ignore
      if (notification.isRead) return;
      // if lastSeen exists and notification.createdAt <= lastSeen, ignore
      final prefs = _ref.read(sharedPreferencesProvider);
      final lastSeenKey = 'notifications_last_seen_$_accountId';
      final lastSeenStr = prefs.getString(lastSeenKey);
      if (lastSeenStr != null) {
        try {
          final lastSeen = DateTime.parse(lastSeenStr);
          if (!notification.createdAt.isAfter(lastSeen)) return;
        } catch (_) {}
      }
      state = state + 1;
    });
  }

  /// Clear badge: persist last-seen timestamp and call server endpoint.
  Future<void> clear() async {
    final prefs = _ref.read(sharedPreferencesProvider);
    final lastSeenKey = 'notifications_last_seen_$_accountId';
    await prefs.setString(lastSeenKey, DateTime.now().toIso8601String());

    final api = _ref.read(misskeyApiProvider);
    try {
      await api?.markNotificationsRead().catchError((_) {});
    } catch (_) {}

    state = 0;
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}

final notificationsBadgeProvider = StateNotifierProvider.autoDispose
    .family<_NotificationsBadgeNotifier, int, String>((ref, accountId) {
      return _NotificationsBadgeNotifier(ref, accountId);
    });
