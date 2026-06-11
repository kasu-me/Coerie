import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streaming/streaming_service.dart';
import '../../data/models/chat_message_model.dart';
import 'account_provider.dart';
import 'misskey_api_provider.dart';
import 'shared_preferences_provider.dart';

/// ホーム画面のアイコンに付ける「未読DM」バッジの状態。
///
/// 値は「最後に確認した時刻（lastSeen）以降に着信した会話の件数」。
/// 通知バッジと同様に、サーバーの既読状態を変更せずローカルの lastSeen で管理する。
class _DmBadgeNotifier extends StateNotifier<int> {
  final Ref _ref;
  final String _accountId;
  StreamSubscription<ChatMessageModel>? _streamSub;

  _DmBadgeNotifier(this._ref, this._accountId) : super(0) {
    _init();
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _streamSub?.cancel();
      _streamSub = null;
      _subscribeStream();
    });
    // 自動再接続成功時に、切断中の取りこぼしを補うため再取得する
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

  String get _lastSeenKey => 'dm_last_seen_$_accountId';

  DateTime? _lastSeen() {
    final prefs = _ref.read(sharedPreferencesProvider);
    final str = prefs.getString(_lastSeenKey);
    if (str == null) return null;
    try {
      return DateTime.parse(str);
    } catch (_) {
      return null;
    }
  }

  Future<void> _init() async {
    await refreshFromApi();
    _subscribeStream();
  }

  /// API から DM・ルームの履歴を取得し、lastSeen 以降に他者から着信した
  /// 会話の件数を数えてバッジ数を更新する。
  Future<void> refreshFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    final myUserId = _ref.read(activeAccountProvider)?.userId ?? '';
    final lastSeen = _lastSeen();

    try {
      final results = await Future.wait([
        api.getChatHistory(room: false, limit: 50),
        api.getChatHistory(room: true, limit: 50),
      ]);
      final messages = [...results[0], ...results[1]];

      final count = messages.where((m) {
        final fromOther = myUserId.isEmpty || m.fromUserId != myUserId;
        final afterLastSeen = lastSeen == null || m.createdAt.isAfter(lastSeen);
        return fromOther && afterLastSeen;
      }).length;

      state = count;
    } catch (_) {
      // ignore errors
    }
  }

  void _subscribeStream() {
    final streaming = _ref.read(streamingServiceProvider);
    if (streaming == null) return;
    _streamSub = streaming.chatMessageStream.listen((message) {
      final myUserId = _ref.read(activeAccountProvider)?.userId ?? '';
      // 自分が送信したメッセージは無視する
      if (myUserId.isNotEmpty && message.fromUserId == myUserId) return;
      // lastSeen 以前のメッセージは無視する
      final lastSeen = _lastSeen();
      if (lastSeen != null && !message.createdAt.isAfter(lastSeen)) return;
      state = state + 1;
    });
  }

  /// バッジをクリアする（DM一覧を開いたタイミングで呼ぶ）。
  /// lastSeen を現在時刻に更新し、以降の着信のみを未読として数える。
  Future<void> clear() async {
    final prefs = _ref.read(sharedPreferencesProvider);
    await prefs.setString(_lastSeenKey, DateTime.now().toIso8601String());
    state = 0;
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}

final dmBadgeProvider = StateNotifierProvider.autoDispose
    .family<_DmBadgeNotifier, int, String>((ref, accountId) {
      return _DmBadgeNotifier(ref, accountId);
    });
