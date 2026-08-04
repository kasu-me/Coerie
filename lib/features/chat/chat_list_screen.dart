import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/chat_room_model.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/dm_badge_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/error_view.dart';

// ─── State ─────────────────────────────────────────────────────────────────

class _ChatHistoryState {
  final List<ChatMessageModel> items;
  final bool isLoading;
  final String? error;

  const _ChatHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  _ChatHistoryState copyWith({
    List<ChatMessageModel>? items,
    bool? isLoading,
    String? error,
  }) => _ChatHistoryState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

// ─── Notifier ──────────────────────────────────────────────────────────────

class _ChatHistoryNotifier extends StateNotifier<_ChatHistoryState> {
  final Ref _ref;

  _ChatHistoryNotifier(this._ref) : super(const _ChatHistoryState()) {
    fetch();
  }

  Future<void> fetch() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await api.getChatHistory(room: false);
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// ─── Room List State / Notifier ──────────────────────────────────────────────

/// 参加中ルームと、そのルームの最新メッセージ（あれば）を束ねたもの。
class _RoomEntry {
  final ChatRoomModel room;
  final ChatMessageModel? lastMessage;

  const _RoomEntry({required this.room, this.lastMessage});
}

class _RoomListState {
  final List<_RoomEntry> items;
  final bool isLoading;
  final String? error;

  const _RoomListState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  _RoomListState copyWith({
    List<_RoomEntry>? items,
    bool? isLoading,
    String? error,
  }) => _RoomListState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class _RoomListNotifier extends StateNotifier<_RoomListState> {
  final Ref _ref;

  _RoomListNotifier(this._ref) : super(const _RoomListState()) {
    fetch();
  }

  Future<void> fetch() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      // 参加中ルーム + 自分が所有するルームをマージ（メッセージ0件でも表示する）。
      final results = await Future.wait([
        api.getChatRoomsJoining(limit: 100),
        api.getChatRoomsOwned(limit: 100),
        api.getChatHistory(room: true, limit: 100),
      ]);
      final joining = results[0] as List<ChatRoomModel>;
      final owned = results[1] as List<ChatRoomModel>;
      final history = results[2] as List<ChatMessageModel>;

      // id で重複排除しつつ全ルームを集約。
      final roomById = <String, ChatRoomModel>{};
      for (final r in [...joining, ...owned]) {
        if (r.id.isNotEmpty) roomById[r.id] = r;
      }

      // 履歴は新しい順なので、ルームごとに最初に出てきたものが最新メッセージ。
      final lastByRoom = <String, ChatMessageModel>{};
      for (final m in history) {
        final rid = m.toRoomId;
        if (rid != null) lastByRoom.putIfAbsent(rid, () => m);
      }

      final entries = roomById.values
          .map((r) => _RoomEntry(room: r, lastMessage: lastByRoom[r.id]))
          .toList();

      // 最新メッセージの時刻（なければルーム作成日時）で降順ソート。
      DateTime sortKey(_RoomEntry e) =>
          e.lastMessage?.createdAt ??
          e.room.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      entries.sort((a, b) => sortKey(b).compareTo(sortKey(a)));

      state = state.copyWith(items: entries, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// ─── Providers ─────────────────────────────────────────────────────────────

final _dmDirectHistoryProvider = StateNotifierProvider.autoDispose
    .family<_ChatHistoryNotifier, _ChatHistoryState, String>(
      (ref, accountId) => _ChatHistoryNotifier(ref),
    );

final _roomListProvider = StateNotifierProvider.autoDispose
    .family<_RoomListNotifier, _RoomListState, String>(
      (ref, accountId) => _RoomListNotifier(ref),
    );

// ─── Screen ────────────────────────────────────────────────────────────────

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // DM一覧を開いたら未読バッジをクリアする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accountId = ref.read(activeAccountProvider)?.id ?? '';
      ref.read(dmBadgeProvider(accountId).notifier).clear();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(activeAccountProvider)?.id ?? '';
    final myUserId = ref.watch(activeAccountProvider)?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ダイレクトメッセージ'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'DM'),
            Tab(icon: Icon(Icons.group_outlined), text: 'グループ'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '新規DM',
            onPressed: () => _showNewDmSheet(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DmListTab(accountId: accountId, myUserId: myUserId),
          _RoomListTab(accountId: accountId),
        ],
      ),
    );
  }

  Future<void> _showNewDmSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => const _NewDmSheet(),
    );
  }
}

// ─── DM List Tab ───────────────────────────────────────────────────────────

class _DmListTab extends ConsumerWidget {
  final String accountId;
  final String myUserId;

  const _DmListTab({required this.accountId, required this.myUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_dmDirectHistoryProvider(accountId));

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(_dmDirectHistoryProvider(accountId).notifier).fetch(),
      );
    }

    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mail_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text('DMはありません', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('右上のアイコンから新しいDMを始めましょう'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(_dmDirectHistoryProvider(accountId).notifier).fetch(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final msg = state.items[i];
          // 自分が送信者かどうか
          final isMe = myUserId.isNotEmpty && msg.fromUserId == myUserId;
          // 会話相手（自分が送信者なら toUser、相手が送信者なら fromUser）
          final partner = isMe ? msg.toUser : msg.fromUser;
          final partnerId = (isMe ? msg.toUserId : msg.fromUserId) ?? '';
          final partnerName =
              partner?.name ?? (partnerId.isNotEmpty ? partnerId : 'ユーザー');
          final partnerAvatar = partner?.avatarUrl;
          final previewText = msg.text ?? (msg.file != null ? '[添付ファイル]' : '');

          return _ConversationTile(
            name: partnerName,
            avatarUrl: partnerAvatar,
            lastMessage: isMe ? '自分: $previewText' : previewText,
            createdAt: msg.createdAt,
            isRead: msg.isRead || isMe,
            onTap: partnerId.isEmpty
                ? null
                : () => context.push(
                    '/dm/user/$partnerId',
                    extra: {'name': partnerName, 'avatarUrl': partnerAvatar},
                  ),
          );
        },
      ),
    );
  }
}

// ─── Room List Tab ─────────────────────────────────────────────────────────

class _RoomListTab extends ConsumerWidget {
  final String accountId;

  const _RoomListTab({required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_roomListProvider(accountId));

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(_roomListProvider(accountId).notifier).fetch(),
      );
    }

    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'グループチャットはありません',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showCreateRoomDialog(context, ref, accountId),
              icon: const Icon(Icons.add),
              label: const Text('グループを作成'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(_roomListProvider(accountId).notifier).fetch(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final entry = state.items[i];
          final room = entry.room;
          final msg = entry.lastMessage;

          final fallbackRoomName = msg?.toRoom?.name ?? '';
          final roomName = room.name.isNotEmpty
              ? room.name
              : (fallbackRoomName.isNotEmpty ? fallbackRoomName : 'グループ');

          final String previewText;
          if (msg == null) {
            previewText = 'まだメッセージはありません';
          } else {
            final senderName = msg.senderName;
            previewText = msg.text != null
                ? '$senderName: ${msg.text}'
                : (msg.file != null ? '$senderName: [添付ファイル]' : '');
          }

          return _ConversationTile(
            name: roomName,
            avatarUrl: null,
            isRoom: true,
            lastMessage: previewText,
            createdAt: msg?.createdAt ?? room.createdAt,
            isRead: msg?.isRead ?? true,
            onTap: () =>
                context.push('/dm/room/${room.id}', extra: {'name': roomName}),
          );
        },
      ),
    );
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    WidgetRef ref,
    String accountId,
  ) async {
    final nameController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('グループを作成'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'グループ名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final room = await api.createChatRoom(name: name);
      if (context.mounted) {
        context.push('/dm/room/${room.id}', extra: {'name': room.name});
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('作成失敗: $e')));
      }
    }
  }
}

// ─── Conversation Tile ─────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime? createdAt;
  final bool isRead;
  final bool isRoom;
  final VoidCallback? onTap;

  const _ConversationTile({
    required this.name,
    this.avatarUrl,
    required this.lastMessage,
    required this.createdAt,
    required this.isRead,
    this.isRoom = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !isRead;

    return ListTile(
      leading: UserAvatar(
        avatarUrl: avatarUrl,
        radius: 24,
        foreground: true,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        icon: isRoom ? Icons.group : Icons.person,
        iconColor: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (createdAt != null)
            Text(
              _relativeTime(createdAt!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread ? theme.colorScheme.primary : null,
              ),
            ),
          if (unread) ...[
            const SizedBox(height: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    return '${dt.month}/${dt.day}';
  }
}

// ─── New DM Sheet ──────────────────────────────────────────────────────────

class _NewDmSheet extends ConsumerStatefulWidget {
  const _NewDmSheet();

  @override
  ConsumerState<_NewDmSheet> createState() => _NewDmSheetState();
}

class _NewDmSheetState extends ConsumerState<_NewDmSheet> {
  final _searchController = TextEditingController();
  List<UserModel> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final api = ref.read(misskeyApiProvider);
      if (api == null) return;
      final results = await api.searchUsers(query: query);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  '新規DM',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'ユーザーを検索',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _search,
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final user = _results[i];
                  return ListTile(
                    leading: UserAvatar(
                      avatarUrl: user.avatarUrl,
                      foreground: true,
                    ),
                    title: Text(user.name),
                    subtitle: Text(user.acct),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(
                        '/dm/user/${user.id}',
                        extra: {'name': user.name, 'avatarUrl': user.avatarUrl},
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
