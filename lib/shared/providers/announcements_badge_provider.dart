import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'misskey_api_provider.dart';
import '../../data/remote/misskey_api.dart';

class _AnnouncementsBadgeNotifier extends StateNotifier<int> {
  final Ref _ref;
  final String _accountId;
  final Set<String> _locallyReadIds = {};

  _AnnouncementsBadgeNotifier(this._ref, this._accountId) : super(0) {
    // If Misskey API isn't ready at construction time, listen and refresh when it becomes available.
    _ref.listen<MisskeyApi?>(misskeyApiProvider, (prev, next) {
      if (next != null) {
        refreshFromApi();
      }
    });
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenKey = 'announcements_last_seen_$_accountId';
    final lastSeenStr = prefs.getString(lastSeenKey);
    DateTime? lastSeen;
    if (lastSeenStr != null) {
      try {
        lastSeen = DateTime.parse(lastSeenStr);
      } catch (_) {}
    }

    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    try {
      final items = await api.getAnnouncements(limit: 50);
      // Count unread: prefer server-provided `isRead` when available,
      // otherwise fall back to last-seen timestamp.
      final unread = items.where((a) {
        final serverRead = a.isRead;
        final afterLastSeen = lastSeen == null || a.createdAt.isAfter(lastSeen);
        final locallyRead = _locallyReadIds.contains(a.id);
        return !serverRead && !locallyRead && afterLastSeen;
      }).length;
      state = unread;
    } catch (_) {}
  }

  Future<void> refreshFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenKey = 'announcements_last_seen_$_accountId';
      final lastSeenStr = prefs.getString(lastSeenKey);
      DateTime? lastSeen;
      if (lastSeenStr != null) {
        try {
          lastSeen = DateTime.parse(lastSeenStr);
        } catch (_) {}
      }

      final items = await api.getAnnouncements(limit: 50);
      final unread = items.where((a) {
        final serverRead = a.isRead;
        final afterLastSeen = lastSeen == null || a.createdAt.isAfter(lastSeen);
        final locallyRead = _locallyReadIds.contains(a.id);
        return !serverRead && !locallyRead && afterLastSeen;
      }).length;
      state = unread;
    } catch (_) {}
  }

  /// Clear badge: persist last-seen timestamp and mark announcements read on server.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenKey = 'announcements_last_seen_$_accountId';
    await prefs.setString(lastSeenKey, DateTime.now().toIso8601String());
    final api = _ref.read(misskeyApiProvider);
    if (api != null) {
      try {
        final items = await api.getAnnouncements(limit: 50);
        // Try to mark each announcement as read on server. Await sequentially to avoid flooding.
        for (final a in items) {
          try {
            await api.readAnnouncement(a.id);
          } catch (_) {}
        }
        // Re-fetch to reflect server-side read flags.
        // clear local temporary read ids because server-side should now reflect reads
        _locallyReadIds.clear();
        await refreshFromApi();
      } catch (_) {}
    } else {
      // No API available; just set local badge to zero.
      state = 0;
      return;
    }

    // If server-side marking succeeded, refreshFromApi() should update state to 0.
    // Ensure client shows cleared badge at minimum.
    if (state != 0) state = 0;
  }

  /// Mark a single announcement read locally (decrement badge count).
  /// Provide the announcement id to remember the local read state until
  /// the server-side state syncs.
  void markOneRead([String? announcementId]) {
    if (announcementId != null) _locallyReadIds.add(announcementId);
    if (state > 0) state = state - 1;
  }
}

final announcementsBadgeProvider = StateNotifierProvider.autoDispose
    .family<_AnnouncementsBadgeNotifier, int, String>((ref, accountId) {
      return _AnnouncementsBadgeNotifier(ref, accountId);
    });
