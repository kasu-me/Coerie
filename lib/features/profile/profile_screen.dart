import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets/mfm_content.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_field_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
import '../../shared/widgets/report_abuse_sheet.dart';
import '../timeline/widgets/note_card.dart';
import 'pinned_notes_provider.dart';
import 'follow_requests_sheet.dart';

class _AppBarIcon extends StatelessWidget {
  final IconData icon;

  const _AppBarIcon(this.icon, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double size = 24;
    const Color color = Colors.white;
    const Color shadowColor = Color(0x66000000);
    const Offset offset = Offset(0, 1);

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: offset,
          child: Icon(icon, size: size, color: shadowColor),
        ),
        Icon(icon, size: size, color: color),
      ],
    );
  }
}

// ユーザー情報プロバイダー
final userProfileProvider = FutureProvider.family<UserModel, String>((
  ref,
  userId,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) throw Exception('未ログイン');
  return api.getUser(userId);
});

// ピン留め投稿プロバイダーは pinned_notes_provider.dart に移動しました

// (リンク検出は MFM レンダラーに委ねるため、手動判定は削除しました)

// ---- 投稿ページネーション ----
class _ProfileNotesState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool hasMore;

  const _ProfileNotesState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = true,
  });
  _ProfileNotesState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? hasMore,
  }) => _ProfileNotesState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
  );
}

class _ProfileNotesNotifier extends StateNotifier<_ProfileNotesState> {
  final Ref _ref;
  final String userId;
  final bool withFiles;

  _ProfileNotesNotifier(this._ref, this.userId, {this.withFiles = false})
    : super(const _ProfileNotesState()) {
    fetch();
  }

  Future<void> fetch({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final untilId = loadMore && state.notes.isNotEmpty
          ? state.notes.last.id
          : null;
      final notes = await api.getUserNotes(
        userId: userId,
        limit: 20,
        withFiles: withFiles,
        untilId: untilId,
      );
      state = state.copyWith(
        isLoading: false,
        notes: loadMore ? [...state.notes, ...notes] : notes,
        hasMore: notes.length >= 20,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = const _ProfileNotesState();
    await fetch();
  }
}

typedef _NotesProviderKey = ({String userId, bool withFiles});
final _profileNotesProvider = StateNotifierProvider.autoDispose
    .family<_ProfileNotesNotifier, _ProfileNotesState, _NotesProviderKey>(
      (ref, p) => _ProfileNotesNotifier(ref, p.userId, withFiles: p.withFiles),
    );

// ---- フォロー/フォロワー リスト状態 ----
class _FollowListState {
  final List<UserModel> users;
  final bool isLoading;
  final bool hasMore;
  const _FollowListState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = true,
  });
  _FollowListState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    bool? hasMore,
  }) => _FollowListState(
    users: users ?? this.users,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
  );
}

class _FollowListNotifier extends StateNotifier<_FollowListState> {
  final Ref _ref;
  final String userId;
  final bool isFollowing; // true=フォロー一覧, false=フォロワー一覧

  _FollowListNotifier(this._ref, this.userId, {required this.isFollowing})
    : super(const _FollowListState()) {
    fetch();
  }

  Future<void> fetch({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final untilId = loadMore && state.users.isNotEmpty
          ? state.users.last.id
          : null;
      final users = isFollowing
          ? await api.getFollowing(userId, limit: 30, untilId: untilId)
          : await api.getFollowers(userId, limit: 30, untilId: untilId);
      state = state.copyWith(
        isLoading: false,
        users: loadMore ? [...state.users, ...users] : users,
        hasMore: users.length >= 30,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

typedef _FollowListKey = ({String userId, bool isFollowing});

final _followListProvider = StateNotifierProvider.autoDispose
    .family<_FollowListNotifier, _FollowListState, _FollowListKey>(
      (ref, p) =>
          _FollowListNotifier(ref, p.userId, isFollowing: p.isFollowing),
    );

class ProfileScreen extends ConsumerWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(e.toString().replaceFirst('Exception: ', '')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(userProfileProvider(userId)),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
        data: (user) => _ProfileBody(user: user, userId: userId),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  final UserModel user;
  final String userId;

  const _ProfileBody({required this.user, required this.userId});

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  final _scrollController = ScrollController();
  late bool _isBlocking;
  late bool _isMuted;
  bool _isLoadingAction = false;

  @override
  void initState() {
    super.initState();
    _isBlocking = widget.user.isBlocking;
    _isMuted = widget.user.isMuted;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(userProfileProvider(widget.userId));
    ref.invalidate(pinnedNotesProvider(widget.userId));
    await Future.wait([
      ref
          .read(
            _profileNotesProvider((
              userId: widget.userId,
              withFiles: false,
            )).notifier,
          )
          .refresh(),
      ref
          .read(
            _profileNotesProvider((
              userId: widget.userId,
              withFiles: true,
            )).notifier,
          )
          .refresh(),
    ]);
  }

  Future<void> _toggleMute() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isLoadingAction) return;
    setState(() => _isLoadingAction = true);
    try {
      if (_isMuted) {
        await api.unmuteUser(widget.userId);
      } else {
        await api.muteUser(widget.userId);
      }
      if (mounted) setState(() => _isMuted = !_isMuted);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _toggleBlock() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isLoadingAction) return;
    if (!_isBlocking) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ユーザーをブロック'),
          content: Text(
            '@${widget.user.username} をブロックしますか？\n'
            'ブロックすると相手からもフォロー解除されます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ブロック'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _isLoadingAction = true);
    try {
      if (_isBlocking) {
        await api.unblockUser(widget.userId);
      } else {
        await api.blockUser(widget.userId);
      }
      if (mounted) setState(() => _isBlocking = !_isBlocking);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _showEditProfileSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditProfileSheet(
        initialName: widget.user.name,
        initialDescription: widget.user.description ?? '',
        userId: widget.userId,
        initialFields: widget.user.fields,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesState = ref.watch(
      _profileNotesProvider((userId: widget.userId, withFiles: false)),
    );
    final mediaState = ref.watch(
      _profileNotesProvider((userId: widget.userId, withFiles: true)),
    );
    final pinnedAsync = ref.watch(pinnedNotesProvider(widget.userId));
    final user = widget.user;
    final activeAccount = ref.watch(activeAccountProvider);
    final isOwnProfile = activeAccount?.userId == widget.userId;

    return DefaultTabController(
      length: 2,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _handleRefresh,
            // 最上部に到達したときだけ RefreshIndicator を発火させる。
            // depth==0: NestedScrollView 外側のオーバースクロール
            // depth==2: タブ内のリストがトップかつ NestedScrollView もトップの場合のみ許可
            notificationPredicate: (notification) {
              if (notification.depth == 0) return true;
              if (notification.depth == 2) {
                return notification.metrics.pixels <= 0 &&
                    _scrollController.hasClients &&
                    _scrollController.position.pixels <= 0;
              }
              return false;
            },
            child: NestedScrollView(
              controller: _scrollController,
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  leading: IconButton(
                    icon: const _AppBarIcon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                    tooltip: '戻る',
                  ),
                  expandedHeight: 200,
                  pinned: true,
                  actions: isOwnProfile
                      ? [
                          IconButton(
                            icon: const _AppBarIcon(Icons.edit_outlined),
                            onPressed: _showEditProfileSheet,
                            tooltip: 'プロフィールを編集',
                          ),
                          IconButton(
                            icon: const _AppBarIcon(Icons.person_add_alt_1),
                            onPressed: _showFollowRequestsSheet,
                            tooltip: 'フォローリクエスト',
                          ),
                        ]
                      : [
                          if (_isLoadingAction)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else
                            PopupMenuButton<String>(
                              icon: const _AppBarIcon(Icons.more_vert),
                              onSelected: (value) async {
                                if (value == 'mute') _toggleMute();
                                if (value == 'block') _toggleBlock();
                                if (value == 'report') {
                                  await showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) =>
                                        ReportAbuseSheet(userId: user.id),
                                  );
                                }
                                if (value == 'clips') {
                                  context.push(
                                    '/users/${user.id}/clips',
                                    extra: user,
                                  );
                                }
                                if (value == 'invalidate') {
                                  final api = ref.read(misskeyApiProvider);
                                  if (api == null) return;
                                  final settings = ref.read(settingsProvider);
                                  if (settings.confirmDestructive) {
                                    final confirmed =
                                        await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('フォロワーを解除'),
                                            content: const Text(
                                              'このユーザーをフォロワーから解除しますか？',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('キャンセル'),
                                              ),
                                              FilledButton(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('解除'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!confirmed) return;
                                  }
                                  setState(() => _isLoadingAction = true);
                                  try {
                                    await api.invalidateFollower(user.id);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('フォロワーを解除しました'),
                                      ),
                                    );
                                    final active = ref.read(
                                      activeAccountProvider,
                                    );
                                    if (active != null) {
                                      ref.invalidate(
                                        _followListProvider((
                                          userId: active.userId,
                                          isFollowing: false,
                                        )),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('操作に失敗しました'),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted)
                                      setState(() => _isLoadingAction = false);
                                  }
                                }
                                if (value == 'open') {
                                  final host = user.host.isNotEmpty
                                      ? user.host
                                      : ref.read(activeAccountProvider)?.host ??
                                            '';
                                  if (host.isEmpty) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('公開URLが見つかりません'),
                                      ),
                                    );
                                    return;
                                  }
                                  final uri = Uri.parse(
                                    'https://$host/@${Uri.encodeComponent(user.username)}',
                                  );
                                  final ok = await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ブラウザで開けませんでした'),
                                      ),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'open',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.open_in_browser),
                                      SizedBox(width: 8),
                                      Text('ブラウザで表示'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'clips',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.bookmark_outline),
                                      SizedBox(width: 8),
                                      Text('クリップを表示'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'mute',
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isMuted
                                            ? Icons.volume_up_outlined
                                            : Icons.volume_off_outlined,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_isMuted ? 'ミュートを解除' : 'ミュートする'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'block',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.block),
                                      const SizedBox(width: 8),
                                      Text(_isBlocking ? 'ブロックを解除' : 'ブロックする'),
                                    ],
                                  ),
                                ),
                                if (user.isFollowed)
                                  PopupMenuItem(
                                    value: 'invalidate',
                                    child: Row(
                                      children: const [
                                        Icon(Icons.person_remove_alt_1),
                                        SizedBox(width: 8),
                                        Text('フォロワーを解除'),
                                      ],
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'report',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flag_outlined,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '通報',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (user.bannerUrl != null)
                          CachedNetworkImage(
                            imageUrl: user.bannerUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stack) => Container(
                              color: theme.colorScheme.primaryContainer,
                            ),
                          )
                        else
                          Container(color: theme.colorScheme.primaryContainer),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black45],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundImage: user.avatarUrl != null
                                  ? CachedNetworkImageProvider(user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? const Icon(Icons.person, size: 36)
                                  : null,
                            ),
                            const Spacer(),
                            if (!isOwnProfile)
                              _FollowButton(
                                userId: widget.userId,
                                initialIsFollowing: user.isFollowing,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.acct,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isOwnProfile && user.isFollowed) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'フォローされています',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (user.description != null) ...[
                          const SizedBox(height: 8),
                          Text(user.description!),
                        ],
                        if (user.fields.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Table(
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            columnWidths: const {
                              0: IntrinsicColumnWidth(),
                              1: FlexColumnWidth(),
                            },
                            children: user.fields
                                .map(
                                  (f) => TableRow(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12.0,
                                          bottom: 8.0,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '${f.name}:',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: MfmContent(
                                          text: f.value,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (user.notesCount != null) ...[
                              _CountChip(count: user.notesCount!, label: '投稿'),
                              const SizedBox(width: 16),
                            ],
                            if (user.followingCount != null) ...[
                              _TappableCountChip(
                                count: user.followingCount!,
                                label: 'フォロー',
                                onTap: () =>
                                    _showFollowList(context, isFollowing: true),
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (user.followersCount != null)
                              _TappableCountChip(
                                count: user.followersCount!,
                                label: 'フォロワー',
                                onTap: () => _showFollowList(
                                  context,
                                  isFollowing: false,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                // カウント行とピン留め投稿の区切り
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      if (pinnedAsync.valueOrNull?.isNotEmpty == true)
                        const SizedBox(height: 4),
                    ],
                  ),
                ),
                if (pinnedAsync.valueOrNull?.isNotEmpty == true) ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final notes = pinnedAsync.value!;
                      if (i >= notes.length) return null;
                      return NoteCard(
                        note: notes[i],
                        pinnedByUser: user,
                        onPinnedChanged: () =>
                            ref.invalidate(pinnedNotesProvider(widget.userId)),
                      );
                    }, childCount: pinnedAsync.value!.length),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 1)),
                ],
                // タブバー
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      tabs: const [
                        Tab(text: '投稿'),
                        Tab(text: 'メディア'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _buildNotesList(notesState, (
                    userId: widget.userId,
                    withFiles: false,
                  ), '投稿がありません'),
                  _buildNotesList(mediaState, (
                    userId: widget.userId,
                    withFiles: true,
                  ), 'メディア付きの投稿がありません'),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: ScrollToTopFab(scrollController: _scrollController),
            ),
          ),
          if (!isOwnProfile)
            Positioned(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'profileMention',
                onPressed: () => context.push(
                  '/compose',
                  extra: {'initialText': '${widget.user.acct} '},
                ),
                tooltip: 'メンションして投稿',
                child: const Icon(Icons.alternate_email),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showFollowList(
    BuildContext context, {
    required bool isFollowing,
  }) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => _FollowListSheet(
          userId: widget.userId,
          isFollowing: isFollowing,
          scrollController: scrollController,
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      context.push('/profile/$selected');
    }
  }

  Future<void> _showFollowRequestsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FollowRequestsSheet(
        profileOwnerId: widget.userId,
        onChanged: () {
          ref.invalidate(
            _followListProvider((userId: widget.userId, isFollowing: false)),
          );
        },
      ),
    );
  }

  Widget _buildNotesList(
    _ProfileNotesState state,
    _NotesProviderKey providerKey,
    String emptyMessage,
  ) {
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.notes.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(child: Center(child: Text(emptyMessage))),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          ref
              .read(_profileNotesProvider(providerKey).notifier)
              .fetch(loadMore: true);
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: state.notes.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == state.notes.length) {
            return state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return NoteCard(note: state.notes[i]);
        },
      ),
    );
  }
}

// ---- フォロー/フォロワー リストシート ----
class _FollowListSheet extends ConsumerWidget {
  final String userId;
  final bool isFollowing;
  final ScrollController scrollController;

  const _FollowListSheet({
    required this.userId,
    required this.isFollowing,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (userId: userId, isFollowing: isFollowing);
    final state = ref.watch(_followListProvider(key));
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            isFollowing ? 'フォロー' : 'フォロワー',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                ref
                    .read(_followListProvider(key).notifier)
                    .fetch(loadMore: true);
              }
              return false;
            },
            child: ListView.builder(
              controller: scrollController,
              itemCount:
                  state.users.length +
                  (state.isLoading || state.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == state.users.length) {
                  return state.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox.shrink();
                }
                final u = state.users[i];
                return _FollowUserTile(
                  user: u,
                  isFollowersList: !isFollowing,
                  profileOwnerId: userId,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FollowUserTile extends ConsumerStatefulWidget {
  final UserModel user;
  final bool isFollowersList;
  final String profileOwnerId;
  const _FollowUserTile({
    required this.user,
    required this.isFollowersList,
    required this.profileOwnerId,
  });

  @override
  ConsumerState<_FollowUserTile> createState() => _FollowUserTileState();
}

class _FollowUserTileState extends ConsumerState<_FollowUserTile> {
  late bool _isFollowing;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.user.isFollowing;
  }

  Future<void> _toggleFollow() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isLoading) return;

    if (_isFollowing) {
      final settings = ref.read(settingsProvider);
      if (settings.confirmDestructive) {
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('フォローを解除'),
                content: const Text('フォローを解除してもよろしいですか？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('解除'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (_isFollowing) {
        await api.unfollowUser(widget.user.id);
      } else {
        await api.followUser(widget.user.id);
      }
      setState(() => _isFollowing = !_isFollowing);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeAccount = ref.watch(activeAccountProvider);
    final isOwnAccount = activeAccount?.userId == widget.user.id;
    final isViewingOwnFollowers =
        widget.isFollowersList &&
        (activeAccount?.userId == widget.profileOwnerId);

    return ListTile(
      onTap: () => Navigator.pop(context, widget.user.id),
      leading: CircleAvatar(
        backgroundImage: widget.user.avatarUrl != null
            ? CachedNetworkImageProvider(widget.user.avatarUrl!)
            : null,
        child: widget.user.avatarUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.user.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.user.isFollowed)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'フォローされています',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: widget.user.description != null
          ? Text(
              widget.user.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : Text(widget.user.acct, style: theme.textTheme.bodySmall),
      trailing: isOwnAccount
          ? null
          : _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  onPressed: _toggleFollow,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    backgroundColor: _isFollowing
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.primary,
                    foregroundColor: _isFollowing
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onPrimary,
                  ),
                  child: Text(_isFollowing ? 'フォロー中' : 'フォロー'),
                ),
              ],
            ),
    );
  }
}

// ---- フォローボタン ----
class _FollowButton extends ConsumerStatefulWidget {
  final String userId;
  final bool initialIsFollowing;
  const _FollowButton({required this.userId, required this.initialIsFollowing});

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  late bool _isFollowing;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.initialIsFollowing;
  }

  Future<void> _toggle() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isLoading) return;

    if (_isFollowing) {
      final settings = ref.read(settingsProvider);
      if (settings.confirmDestructive) {
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('フォローを解除'),
                content: const Text('フォローを解除してもよろしいですか？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('解除'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (_isFollowing) {
        await api.unfollowUser(widget.userId);
      } else {
        await api.followUser(widget.userId);
      }
      setState(() => _isFollowing = !_isFollowing);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final theme = Theme.of(context);
    return FilledButton.tonal(
      onPressed: _toggle,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
        backgroundColor: _isFollowing
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.primary,
        foregroundColor: _isFollowing
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onPrimary,
      ),
      child: Text(_isFollowing ? 'フォロー中' : 'フォロー'),
    );
  }
}

// プロフィール編集シート
// build() 内で MediaQuery.of(context).viewInsets を使うと、シート dismissal 時に
// 要素が deactivate → unmount される前にキーボードアニメーションで MediaQuery が
// 変化し、非アクティブな要素が _dirtyElements に追加される。
// BuildOwner.buildScope がその要素をビルドしようとすると _elements.contains(element)
// アサーションが失敗するため、WidgetsBindingObserver.didChangeMetrics で
// キーボード高さをローカル状態として管理し InheritedWidget 依存を完全に排除する。
class _EditProfileSheet extends ConsumerStatefulWidget {
  final String initialName;
  final String initialDescription;
  final String userId;
  final List<UserFieldModel> initialFields;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialDescription,
    required this.userId,
    this.initialFields = const [],
  });

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _FieldEntry {
  final TextEditingController nameController;
  final TextEditingController valueController;
  _FieldEntry({String name = '', String value = ''})
    : nameController = TextEditingController(text: name),
      valueController = TextEditingController(text: value);
  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet>
    with WidgetsBindingObserver {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final List<_FieldEntry> _fields;
  bool _saving = false;
  double _keyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descController = TextEditingController(text: widget.initialDescription);
    _fields = widget.initialFields
        .map((f) => _FieldEntry(name: f.name, value: f.value))
        .toList();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _descController.dispose();
    for (final e in _fields) e.dispose();
    super.dispose();
  }

  void _addField() => setState(() => _fields.add(_FieldEntry()));
  void _removeFieldAt(int i) => setState(() => _fields.removeAt(i));

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final newHeight = view.viewInsets.bottom / view.devicePixelRatio;
    if (newHeight != _keyboardHeight) {
      // Defer the state update to the next frame to avoid triggering
      // widget tree mutations during transient metric changes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _keyboardHeight = newHeight);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(misskeyApiProvider);
      final fieldsPayload = _fields
          .map(
            (e) => {
              'name': e.nameController.text.trim(),
              'value': e.valueController.text.trim(),
            },
          )
          .where(
            (m) =>
                (m['name'] as String).isNotEmpty ||
                (m['value'] as String).isNotEmpty,
          )
          .toList();
      await api?.updateProfile(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        fields: fieldsPayload.isNotEmpty ? fieldsPayload : null,
      );
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(userProfileProvider(widget.userId));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + _keyboardHeight + bottomSafe,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('プロフィールを編集', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名前',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: '自己紹介',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          Text('追加情報', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._fields.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: e.nameController,
                      decoration: const InputDecoration(
                        labelText: '項目',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: e.valueController,
                      decoration: const InputDecoration(
                        labelText: '値',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _removeFieldAt(i),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '削除',
                  ),
                ],
              ),
            );
          }),
          FilledButton.tonal(
            onPressed: _addField,
            child: const Text('フィールドを追加'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;

  const _CountChip({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _TappableCountChip extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;

  const _TappableCountChip({
    required this.count,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$count',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
