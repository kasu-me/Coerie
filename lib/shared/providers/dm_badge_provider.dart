import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streaming/streaming_service.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/remote/misskey_api.dart';
import 'account_provider.dart';
import 'last_seen_badge_notifier.dart';

/// ホーム画面のアイコンに付ける「未読DM」バッジの状態。
///
/// 値は「lastSeen 以降に他者から着信したメッセージの件数」。
/// 通知バッジと同様に、サーバーの既読状態は変更しない。
class _DmBadgeNotifier extends LastSeenBadgeNotifier<ChatMessageModel> {
  _DmBadgeNotifier(super.ref, super.accountId);

  @override
  String get prefsKeyPrefix => 'dm_last_seen';

  @override
  Future<List<ChatMessageModel>> fetchItems(MisskeyApi api) async {
    final results = await Future.wait([
      api.getChatHistory(room: false, limit: 50),
      api.getChatHistory(room: true, limit: 50),
    ]);
    return [...results[0], ...results[1]];
  }

  @override
  DateTime createdAtOf(ChatMessageModel item) => item.createdAt;

  /// 自分が送信したメッセージは数えない。
  /// 自分のIDが取れない場合は絞り込めないため、すべて他者扱いにする。
  @override
  bool isUnread(ChatMessageModel item) {
    final myUserId = ref.read(activeAccountProvider)?.userId ?? '';
    return myUserId.isEmpty || item.fromUserId != myUserId;
  }

  @override
  Stream<ChatMessageModel> streamOf(StreamingService streaming) =>
      streaming.chatMessageStream;
}

final dmBadgeProvider = StateNotifierProvider.autoDispose
    .family<_DmBadgeNotifier, int, String>((ref, accountId) {
      return _DmBadgeNotifier(ref, accountId);
    });
