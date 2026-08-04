import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/user_model.dart';
import '../../data/remote/misskey_api.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/error_view.dart';

// ─── State ─────────────────────────────────────────────────────────────────

class _ThreadState {
  final List<ChatMessageModel> messages; // newest first
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isSending;
  final String? error;

  const _ThreadState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.isSending = false,
    this.error,
  });

  _ThreadState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isSending,
    String? error,
  }) => _ThreadState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    isSending: isSending ?? this.isSending,
    error: error,
  );
}

// ─── Thread Params ─────────────────────────────────────────────────────────

class _ThreadParams {
  final String? userId;
  final String? roomId;
  final String accountId;

  const _ThreadParams({this.userId, this.roomId, required this.accountId});

  @override
  bool operator ==(Object other) =>
      other is _ThreadParams &&
      other.userId == userId &&
      other.roomId == roomId &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(userId, roomId, accountId);
}

// ─── Notifier ──────────────────────────────────────────────────────────────

class _ThreadNotifier extends StateNotifier<_ThreadState> {
  final Ref _ref;
  final _ThreadParams _params;
  static const _limit = 30;

  _ThreadNotifier(this._ref, this._params) : super(const _ThreadState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final msgs = await _fetchMessages(api);
      state = state.copyWith(
        messages: msgs,
        isLoading: false,
        hasMore: msgs.length >= _limit,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => _loadInitial();

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.messages.isEmpty) return;
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final oldest = state.messages.last;
      final msgs = await _fetchMessages(api, untilId: oldest.id);
      state = state.copyWith(
        messages: [...state.messages, ...msgs],
        isLoadingMore: false,
        hasMore: msgs.length >= _limit,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<List<ChatMessageModel>> _fetchMessages(
    MisskeyApi api, {
    String? untilId,
  }) {
    if (_params.userId != null) {
      return api.getChatUserTimeline(
        userId: _params.userId!,
        limit: _limit,
        untilId: untilId,
      );
    } else {
      return api.getChatRoomTimeline(
        roomId: _params.roomId!,
        limit: _limit,
        untilId: untilId,
      );
    }
  }

  Future<void> sendMessage(String text) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null || text.trim().isEmpty) return;
    state = state.copyWith(isSending: true);
    try {
      final ChatMessageModel sent;
      if (_params.userId != null) {
        sent = await api.sendChatMessageToUser(
          toUserId: _params.userId!,
          text: text.trim(),
        );
      } else {
        sent = await api.sendChatMessageToRoom(
          toRoomId: _params.roomId!,
          text: text.trim(),
        );
      }
      state = state.copyWith(
        messages: [sent, ...state.messages],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(isSending: false);
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    await api.deleteChatMessage(messageId);
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }
}

// ─── Provider ──────────────────────────────────────────────────────────────

final _threadProvider = StateNotifierProvider.autoDispose
    .family<_ThreadNotifier, _ThreadState, _ThreadParams>(
      (ref, params) => _ThreadNotifier(ref, params),
    );

/// ルームの参加メンバー一覧
final _roomMembersProvider = FutureProvider.autoDispose
    .family<List<UserModel>, String>((ref, roomId) async {
      final api = ref.watch(misskeyApiProvider);
      if (api == null) return const [];
      return api.getChatRoomMembers(roomId: roomId);
    });

// ─── Screen ────────────────────────────────────────────────────────────────

class ChatThreadScreen extends ConsumerStatefulWidget {
  final String? userId;
  final String? roomId;
  final String partnerName;
  final String? partnerAvatarUrl;

  const ChatThreadScreen({
    super.key,
    this.userId,
    this.roomId,
    required this.partnerName,
    this.partnerAvatarUrl,
  });

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  _ThreadParams get _params {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    return _ThreadParams(
      userId: widget.userId,
      roomId: widget.roomId,
      accountId: accountId,
    );
  }

  void _onScroll() {
    final pos = _scrollController.position;
    // reverse: true なので maxScrollExtent 側がリストの「先頭（古いメッセージ）」
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(_threadProvider(_params).notifier).loadMore();
    }
    final shouldShow = pos.pixels > 200;
    if (_showScrollToBottom != shouldShow) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    try {
      await ref.read(_threadProvider(_params).notifier).sendMessage(text);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('送信失敗: $e')));
      }
    }
  }

  Future<void> _showRoomMembers(BuildContext context) async {
    final roomId = widget.roomId;
    if (roomId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RoomMembersSheet(roomId: roomId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(activeAccountProvider)?.id ?? '';
    final myUserId = ref.watch(activeAccountProvider)?.userId ?? '';
    final params = _ThreadParams(
      userId: widget.userId,
      roomId: widget.roomId,
      accountId: accountId,
    );
    final state = ref.watch(_threadProvider(params));

    final isRoom = widget.roomId != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          // 1対1 はタップで相手のプロフィールへ。グループはメンバー一覧を開く。
          onTap: isRoom
              ? () => _showRoomMembers(context)
              : () => context.push('/profile/${widget.userId}'),
          child: Row(
            children: [
              const SizedBox(width: 4),
              UserAvatar(
                avatarUrl: widget.partnerAvatarUrl,
                radius: 16,
                foreground: true,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                icon: isRoom ? Icons.group : Icons.person,
                iconSize: 18,
                iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.partnerName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isRoom)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'メンバー',
              onPressed: () => _showRoomMembers(context),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
            onPressed: () =>
                ref.read(_threadProvider(params).notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _MessageList(
                  state: state,
                  myUserId: myUserId,
                  scrollController: _scrollController,
                  fallbackAvatarUrl: widget.partnerAvatarUrl,
                  onDeleteMessage: (id) => ref
                      .read(_threadProvider(params).notifier)
                      .deleteMessage(id),
                ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'scroll_to_bottom',
                      onPressed: () => _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
              ],
            ),
          ),
          _MessageInputBar(
            controller: _textController,
            isSending: state.isSending,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ─── Message List ──────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final _ThreadState state;
  final String myUserId;
  final ScrollController scrollController;
  final Future<void> Function(String) onDeleteMessage;

  /// 1対1 DM のメッセージには `fromUser` が含まれないため、
  /// 受信メッセージのアバターとして使う相手のアバターURL。
  final String? fallbackAvatarUrl;

  const _MessageList({
    required this.state,
    required this.myUserId,
    required this.scrollController,
    required this.onDeleteMessage,
    this.fallbackAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'エラーが発生しました\n${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            const Text('最初のメッセージを送りましょう'),
          ],
        ),
      );
    }

    // reverse: true で messages[0](最新)が下に表示される
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: state.messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        // リストの末尾（スクロール上端）にローディングを表示
        if (i == state.messages.length) {
          return state.isLoadingMore
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox.shrink();
        }
        final msg = state.messages[i];
        final isMe = msg.fromUserId == myUserId;
        // 直前のメッセージと同じ送信者かチェック（アバター表示の省略用）
        final prevMsg = i > 0 ? state.messages[i - 1] : null;
        final isConsecutive =
            prevMsg != null && prevMsg.fromUserId == msg.fromUserId;
        return _MessageBubble(
          message: msg,
          isMe: isMe,
          showAvatar: !isMe && !isConsecutive,
          fallbackAvatarUrl: fallbackAvatarUrl,
          onDelete: isMe
              ? () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('メッセージを削除'),
                      content: const Text('このメッセージを削除しますか？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('キャンセル'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await onDeleteMessage(msg.id);
                }
              : null,
        );
      },
    );
  }
}

// ─── Message Bubble ────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final bool showAvatar;
  final String? fallbackAvatarUrl;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
    this.fallbackAvatarUrl,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 相手側アバター（タップで送信者のプロフィールへ）
          if (!isMe)
            SizedBox(
              width: 36,
              child: showAvatar
                  ? GestureDetector(
                      onTap: message.fromUserId.isEmpty
                          ? null
                          : () =>
                                context.push('/profile/${message.fromUserId}'),
                      child: UserAvatar(
                        avatarUrl: message.senderAvatarUrl ?? fallbackAvatarUrl,
                        radius: 16,
                        foreground: true,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        iconSize: 16,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
          if (!isMe) const SizedBox(width: 4),
          // バブル + タイムスタンプ
          Flexible(
            child: GestureDetector(
              onLongPress: onDelete,
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: isMe
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                    ),
                    child: _BubbleContent(message: message, isMe: isMe),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatHm(message.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bubble Content ────────────────────────────────────────────────────────

class _BubbleContent extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;

  const _BubbleContent({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    final widgets = <Widget>[];

    // 添付ファイル（画像）
    if (message.file != null) {
      final fileType = message.file!['type'] as String? ?? '';
      final fileUrl = message.file!['url'] as String?;
      if (fileUrl != null && fileType.startsWith('image/')) {
        widgets.add(
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
              child: CachedNetworkImage(
                imageUrl: fileUrl,
                cacheManager: AppCacheManager(),
                width: 240,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox(
                  width: 240,
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, _, _) => const SizedBox(
                  width: 240,
                  height: 60,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
        );
      } else if (fileUrl != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.attach_file, size: 16, color: textColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    message.file!['name'] as String? ?? 'ファイル',
                    style: TextStyle(color: textColor, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // テキスト
    if (message.text != null && message.text!.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            message.text!,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
          ),
        ),
      );
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(isMe ? 18 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      ),
    );
  }
}

// ─── Message Input Bar ─────────────────────────────────────────────────────

class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _MessageInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'メッセージを入力...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(128),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            isSending
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      padding: const EdgeInsets.all(10),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Room Members Sheet ──────────────────────────────────────────────────────

class _RoomMembersSheet extends ConsumerWidget {
  final String roomId;

  const _RoomMembersSheet({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(_roomMembersProvider(roomId));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'メンバー',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(
                  message: 'メンバーの読み込みに失敗しました',
                  onRetry: () => ref.invalidate(_roomMembersProvider(roomId)),
                ),
                data: (members) {
                  if (members.isEmpty) {
                    return const Center(child: Text('メンバーがいません'));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: members.length,
                    itemBuilder: (context, i) {
                      final u = members[i];
                      return ListTile(
                        leading: UserAvatar(
                          avatarUrl: u.avatarUrl,
                          foreground: true,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                        title: Text(
                          u.name.isNotEmpty ? u.name : u.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(u.acct),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/profile/${u.id}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
