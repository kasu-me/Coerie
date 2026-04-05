import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/streaming/streaming_service.dart';
import 'misskey_api_provider.dart';
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
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenKey = 'notifications_last_seen_$_accountId';
    final lastSeenStr = prefs.getString(lastSeenKey);
    DateTime? lastSeen;
    if (lastSeenStr != null) {
      try {
        lastSeen = DateTime.parse(lastSeenStr);
      } catch (_) {}
    }

    final api = _ref.read(misskeyApiProvider);
    if (api == null) {
      _subscribeStream();
      return;
    }

    try {
      final items = await api.getNotifications(limit: 50);
      // unread when server reports !isRead AND createdAt is after lastSeen (if set)
      final unread = items.where((n) {
        final serverUnread = !(n.isRead);
        final afterLastSeen = lastSeen == null || n.createdAt.isAfter(lastSeen);
        return serverUnread && afterLastSeen;
      }).length;
      state = unread;
    } catch (_) {
      // ignore errors
    }
    _subscribeStream();
  }

  /// API から通知を再取得してバッジ数を更新する。
  /// 主に WebSocket が切断されているときのフォールバックとして利用する。
  Future<void> refreshFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
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
    _streamSub = streaming.notificationStream.listen((notification) async {
      // if notification is already marked read on server, ignore
      if (notification.isRead) return;
      // if lastSeen exists and notification.createdAt <= lastSeen, ignore
      final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
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
