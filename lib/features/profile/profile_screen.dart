import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/errors/api_error_message.dart';
import '../../shared/widgets/mfm_content.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_field_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
import '../../shared/widgets/report_abuse_sheet.dart';
import '../timeline/widgets/note_card.dart';
import 'pinned_notes_provider.dart';
import 'follow_requests_sheet.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/providers/paged_notifier.dart';

class _AppBarIcon extends StatelessWidget {
  final IconData icon;

  const _AppBarIcon(this.icon);

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

// ユーザー情報プロバイダー。
// autoDispose により、閲覧したユーザーぶんの UserModel が際限なく残らないようにする。
final userProfileProvider = FutureProvider.autoDispose
    .family<UserModel, String>((ref, userId) async {
      final api = ref.watch(misskeyApiProvider);
      if (api == null) throw const AppException('ログインが必要です');
      return api.getUser(userId);
    });

// ピン留め投稿プロバイダーは pinned_notes_provider.dart に移動しました

// (リンク検出は MFM レンダラーに委ねるため、手動判定は削除しました)

// ---- 投稿ページネーション ----
class _ProfileNotesNotifier extends PagedNotifier<NoteModel> {
  final Ref _ref;
  final String userId;
  final bool withFiles;
  final bool withReplies;

  _ProfileNotesNotifier(
    this._ref,
    this.userId, {
    this.withFiles = false,
    this.withReplies = false,
  }) {
    fetch();
  }

  @override
  String cursorOf(NoteModel item) => item.id;

  @override
  Future<List<NoteModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    return api.getUserNotes(
      userId: userId,
      limit: pageSize,
      withFiles: withFiles,
      withReplies: withReplies,
      untilId: untilId,
    );
  }
}

typedef _NotesProviderKey = ({String userId, bool withFiles, bool withReplies});
final _profileNotesProvider = StateNotifierProvider.autoDispose
    .family<_ProfileNotesNotifier, PagedState<NoteModel>, _NotesProviderKey>(
      (ref, p) => _ProfileNotesNotifier(
        ref,
        p.userId,
        withFiles: p.withFiles,
        withReplies: p.withReplies,
      ),
    );

// タブ順に対応するプロバイダーキー（0:投稿 / 1:投稿と返信 / 2:メディア）
_NotesProviderKey _notesKeyForTab(String userId, int tabIndex) =>
    switch (tabIndex) {
      1 => (userId: userId, withFiles: false, withReplies: true),
      2 => (userId: userId, withFiles: true, withReplies: false),
      _ => (userId: userId, withFiles: false, withReplies: false),
    };

// ---- フォロー/フォロワー リスト ----
class _FollowListNotifier extends PagedNotifier<FollowingModel> {
  final Ref _ref;
  final String userId;
  final bool isFollowing; // true=フォロー一覧, false=フォロワー一覧

  _FollowListNotifier(this._ref, this.userId, {required this.isFollowing}) {
    fetch();
  }

  @override
  int get pageSize => 30;

  /// カーソルはユーザーIDではなくフォロー関係レコードのID。
  /// 取り違えるとページングが壊れる（[FollowingModel] のコメント参照）。
  @override
  String cursorOf(FollowingModel item) => item.id;

  @override
  Future<List<FollowingModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    final items = isFollowing
        ? await api.getFollowing(userId, limit: pageSize, untilId: untilId)
        : await api.getFollowers(userId, limit: pageSize, untilId: untilId);

    // users/relation で一括取得したリレーション情報を各 UserModel に反映する。
    // 失敗した場合は元の items をそのまま使う。
    try {
      final relations = await api.getUsersRelation(
        items.map((f) => f.user.id).toList(),
      );
      if (relations.isEmpty) return items;
      return items.map((f) {
        final rel = relations[f.user.id];
        if (rel == null) return f;
        return f.copyWith(
          user: f.user.copyWith(
            isFollowing: rel['isFollowing'] as bool? ?? f.user.isFollowing,
            isFollowed: rel['isFollowed'] as bool? ?? f.user.isFollowed,
            isBlocking: rel['isBlocking'] as bool? ?? f.user.isBlocking,
            isMuted: rel['isMuted'] as bool? ?? f.user.isMuted,
          ),
        );
      }).toList();
    } catch (_) {
      return items;
    }
  }
}

typedef _FollowListKey = ({String userId, bool isFollowing});

final _followListProvider = StateNotifierProvider.autoDispose
    .family<_FollowListNotifier, PagedState<FollowingModel>, _FollowListKey>(
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
        error: (e, _) => ErrorView(
          message: apiErrorMessage(e, fallback: 'プロフィールを取得できませんでした'),
          onRetry: () => ref.invalidate(userProfileProvider(userId)),
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

class _ProfileBodyState extends ConsumerState<_ProfileBody>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final TabController _tabController;

  /// 一度でも開いたタブの index。
  /// ここに入っているタブのプロバイダーは build で watch し続けることで、
  /// autoDispose による破棄（＝タブを戻したときの1ページ目からの再取得）を防ぐ。
  /// 未訪問のタブを含めないのは、画面を開いた時点で3タブぶんの API を
  /// 叩かないようにするため。
  final _activatedTabs = <int>{0};

  /// タブごとの「コンテンツ部分だけの」スクロール量。
  /// 画面全体が単一の CustomScrollView なので、絶対オフセットを覚えて復元すると
  /// ヘッダー（＝タブバー）の位置まで一緒に動いてしまう。タブバーが上端に
  /// 固定された状態を原点とする相対量で持ち、切り替えでタブバーを動かさない。
  final _tabContentOffsets = <int, double>{};

  /// タブバーが上端に固定されるスクロールオフセット。
  /// 自己紹介文や追加情報の量でヘッダーの高さが変わるため、実測して保持する。
  double? _tabBarPinOffset;

  /// [_tabBarPinOffset] の実測に使う、固定表示されるタブバー領域のキー。
  final _tabBarHeaderKey = GlobalKey();

  /// 表示中のタブ。TabController のリスナーは index が変わらない通知でも
  /// 呼ばれるため、実際に切り替わったかの判定に使う。
  int _currentTab = 0;

  late bool _isBlocking;
  late bool _isMuted;
  late bool _isFollowed;
  bool _isLoadingAction = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _isBlocking = widget.user.isBlocking;
    _isMuted = widget.user.isMuted;
    _isFollowed = widget.user.isFollowed;
  }

  void _onTabChanged() {
    final next = _tabController.index;
    if (next == _currentTab || !mounted) return;

    _tabContentOffsets[_currentTab] = _currentContentOffset();
    _currentTab = next;
    _activatedTabs.add(next);
    // タブ切り替えで表示するスライバーを差し替える
    setState(() {});
    // 差し替え後のレイアウトが終わるまで待つ。先に jumpTo すると、
    // 切り替え前のタブの（短いこともある）maxScrollExtent でクランプされる。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreContentOffset(next),
    );
  }

  /// タブバーが上端に固定された位置を原点とした、現在のコンテンツのスクロール量。
  /// ヘッダーがまだ見えている間はコンテンツを送れないので必ず 0 になる。
  double _currentContentOffset() {
    final pin = _tabBarPinOffset;
    if (pin == null || !_scrollController.hasClients) return 0;
    return (_scrollController.offset - pin).clamp(0.0, double.infinity);
  }

  void _restoreContentOffset(int tab) {
    if (!mounted || !_scrollController.hasClients) return;
    final pin = _tabBarPinOffset;
    if (pin == null) return;
    // ヘッダーが見えている状態でコンテンツを送ると、タブバーが上端まで
    // 引き上げられて「切り替えでタブバーが動く」ことになる。位置は動かさず、
    // コンテンツは先頭から見せる。
    if (_scrollController.offset < pin) return;
    final target = (pin + (_tabContentOffsets[tab] ?? 0)).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if ((_scrollController.offset - target).abs() > 0.5) {
      _scrollController.jumpTo(target);
    }
  }

  /// タブバーが上端に固定される位置を実測する。
  ///
  /// 固定済みのときは見かけの位置が動かないため算出できない。その場合は
  /// 前回値を保つ（ヘッダーの高さは自己紹介文の変化程度でしか変わらない）。
  void _measureTabBarPinOffset() {
    if (!mounted || !_scrollController.hasClients) return;
    final box = _tabBarHeaderKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final pinnedY = kToolbarHeight + MediaQuery.viewPaddingOf(context).top;
    final currentY = box.localToGlobal(Offset.zero).dy;
    if (currentY <= pinnedY + 0.5) return;
    _tabBarPinOffset = (_scrollController.offset + (currentY - pinnedY)).clamp(
      0.0,
      double.infinity,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(userProfileProvider(widget.userId));
    ref.invalidate(pinnedNotesProvider(widget.userId));
    // 各タブが1ページ目から取り直されるため、保存済みのスクロール位置は
    // 対応する投稿を失って意味をなさなくなる。
    _tabContentOffsets.clear();
    await Future.wait([
      for (final i in _activatedTabs)
        ref
            .read(
              _profileNotesProvider(_notesKeyForTab(widget.userId, i)).notifier,
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
            '${widget.user.acct} をブロックしますか？\n'
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
    // ヘッダーの高さはプロフィールの内容で変わるので、レイアウト確定後に測り直す。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measureTabBarPinOffset(),
    );

    final theme = Theme.of(context);
    final tabIndex = _currentTab;
    final notesState = ref.watch(
      _profileNotesProvider(_notesKeyForTab(widget.userId, tabIndex)),
    );
    // 表示していないタブも watch し続けて autoDispose を抑止する。
    // 破棄させるとタブを戻すたびに1ページ目から再取得となり、読み込み中の
    // プレースホルダー表示まで一覧が縮んでスクロール位置を保てなくなる。
    for (final i in _activatedTabs) {
      if (i == tabIndex) continue;
      ref.watch(_profileNotesProvider(_notesKeyForTab(widget.userId, i)));
    }
    final pinnedAsync = ref.watch(pinnedNotesProvider(widget.userId));
    // ナビゲーションバーと投稿が重ならないよう、最下部に確保する余白
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom + 88;
    final user = widget.user;
    final activeAccount = ref.watch(activeAccountProvider);
    final isOwnProfile = activeAccount?.userId == widget.userId;

    final tabBar = TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: '投稿'),
        Tab(text: '投稿と返信'),
        Tab(text: 'メディア'),
      ],
    );

    // 読み込み中・空表示のプレースホルダーに与える固定高さ。
    //
    // ここで SliverFillRemaining を使うと、スクロール位置が必ず最上部まで
    // 巻き戻る。remainingPaintExtent（現在のスクロール位置に依存する値）を
    // そのまま scrollExtent として報告するため、「位置がクランプされる →
    // ヘッダーが再び現れて remainingPaintExtent が減る → 総スクロール量が
    // 縮んでさらにクランプされる」というループになるため。
    // スクロール位置に依存しない値を渡してループを断ち切る。
    // 値はヘッダーを畳み切った状態の残り高さ（＝畳んだ位置でちょうど
    // 止まる高さ）に合わせている。
    final placeholderHeight =
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewPaddingOf(context).top -
                kToolbarHeight -
                tabBar.preferredSize.height)
            .clamp(0.0, double.infinity);

    // NestedScrollView はフリング中に inner/outer のスクロール同期がずれ、
    // リストが先頭に達する前にヘッダーが展開されてしまうため、
    // 全体を単一の CustomScrollView で構成しタブ内容をスライバーとして差し替える。
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _handleRefresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 下端付近に到達したら表示中タブの続きを読み込む
              if (n is ScrollUpdateNotification &&
                  n.metrics.axis == Axis.vertical &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                ref
                    .read(
                      _profileNotesProvider(
                        _notesKeyForTab(widget.userId, _currentTab),
                      ).notifier,
                    )
                    .fetch(loadMore: true);
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
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
                                  if (!context.mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ブラウザで開けませんでした'),
                                      ),
                                    );
                                  }
                                }
                                if (value == 'edit') {
                                  _showEditProfileSheet();
                                }
                                if (value == 'follow_requests') {
                                  _showFollowRequestsSheet();
                                }
                                if (value == 'clips') {
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/clips',
                                    extra: user,
                                  );
                                }
                                if (value == 'pages') {
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/pages',
                                    extra: user,
                                  );
                                }
                                if (value == 'gallery') {
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/gallery',
                                    extra: user,
                                  );
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
                                  value: 'edit',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.edit_outlined),
                                      SizedBox(width: 8),
                                      Text('プロフィール編集'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'follow_requests',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.person_add_alt_1),
                                      SizedBox(width: 8),
                                      Text('フォローリクエスト'),
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
                                  value: 'pages',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.description_outlined),
                                      SizedBox(width: 8),
                                      Text('ページを表示'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'gallery',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.collections_outlined),
                                      SizedBox(width: 8),
                                      Text('ギャラリーを表示'),
                                    ],
                                  ),
                                ),
                              ],
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
                                if (value == 'dm') {
                                  context.push(
                                    '/dm/user/${widget.userId}',
                                    extra: {
                                      'name': user.name,
                                      'avatarUrl': user.avatarUrl,
                                    },
                                  );
                                }
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
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/clips',
                                    extra: user,
                                  );
                                }
                                if (value == 'pages') {
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/pages',
                                    extra: user,
                                  );
                                }
                                if (value == 'gallery') {
                                  if (!context.mounted) return;
                                  context.push(
                                    '/users/${user.id}/gallery',
                                    extra: user,
                                  );
                                }
                                if (value == 'invalidate') {
                                  final api = ref.read(misskeyApiProvider);
                                  if (api == null) return;
                                  if (!context.mounted) return;
                                  final confirmed = await confirmAction(
                                    context,
                                    ref,
                                    title: 'フォロワーを解除',
                                    message: 'このユーザーをフォロワーから解除しますか？',
                                    confirmLabel: '解除',
                                  );
                                  if (!confirmed) return;
                                  // 楽観的にバッジを即時非表示にする
                                  final prevFollowed = _isFollowed;
                                  setState(() {
                                    _isLoadingAction = true;
                                    _isFollowed = false;
                                  });
                                  try {
                                    await api.invalidateFollower(user.id);
                                    if (!context.mounted) return;
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
                                    if (context.mounted) {
                                      // 失敗したら状態を元に戻す
                                      setState(
                                        () => _isFollowed = prevFollowed,
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('操作に失敗しました'),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoadingAction = false);
                                    }
                                  }
                                }
                                if (value == 'open') {
                                  final host = user.host.isNotEmpty
                                      ? user.host
                                      : ref.read(activeAccountProvider)?.host ??
                                            '';
                                  if (host.isEmpty) {
                                    if (!context.mounted) return;
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
                                  if (!context.mounted) return;
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
                                  value: 'dm',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.mail_outline),
                                      SizedBox(width: 8),
                                      Text('ダイレクトメッセージ'),
                                    ],
                                  ),
                                ),
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
                                  value: 'pages',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.description_outlined),
                                      SizedBox(width: 8),
                                      Text('ページを表示'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'gallery',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.collections_outlined),
                                      SizedBox(width: 8),
                                      Text('ギャラリーを表示'),
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
                                if (_isFollowed)
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
                            cacheManager: AppCacheManager(),
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
                            UserAvatar(
                              avatarUrl: user.avatarUrl,
                              radius: 36,
                              iconSize: 36,
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
                            if (!isOwnProfile && _isFollowed) ...[
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
                // カウント行とタブバーの区切り
                const SliverToBoxAdapter(child: Divider(height: 1)),
                // タブバー
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabBar,
                    headerKey: _tabBarHeaderKey,
                  ),
                ),
                // タブ内容
                ..._buildNotesSlivers(
                  notesState,
                  switch (tabIndex) {
                    1 => '投稿・返信がありません',
                    2 => 'メディア付きの投稿がありません',
                    _ => '投稿がありません',
                  },
                  pinnedNotes: tabIndex == 0
                      ? (pinnedAsync.valueOrNull ?? [])
                      : const [],
                  bottomInset: bottomInset,
                  placeholderHeight: placeholderHeight,
                ),
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
    );
  }

  Future<void> _showFollowList(
    BuildContext context, {
    required bool isFollowing,
  }) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    if (!context.mounted) return;
    if (selected != null) {
      context.push('/profile/$selected');
    }
  }

  Future<void> _showFollowRequestsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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

  List<Widget> _buildNotesSlivers(
    PagedState<NoteModel> state,
    String emptyMessage, {
    required double placeholderHeight,
    List<NoteModel> pinnedNotes = const [],
    double bottomInset = 0,
  }) {
    if (state.isLoading && state.items.isEmpty && pinnedNotes.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: placeholderHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    return [
      if (pinnedNotes.isNotEmpty) ...[
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => NoteCard(
              note: pinnedNotes[i],
              pinnedByUser: widget.user,
              onPinnedChanged: () =>
                  ref.invalidate(pinnedNotesProvider(widget.userId)),
            ),
            childCount: pinnedNotes.length,
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
      ],
      if (state.items.isEmpty && !state.isLoading && pinnedNotes.isEmpty)
        SliverToBoxAdapter(
          child: SizedBox(
            height: placeholderHeight,
            child: Center(child: Text(emptyMessage)),
          ),
        ),
      if (state.items.isNotEmpty || state.isLoading)
        SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            if (i == state.items.length) {
              return state.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink();
            }
            return NoteCard(note: state.items[i]);
          }, childCount: state.items.length + (state.hasMore ? 1 : 0)),
        ),
      // ナビゲーションバー・FAB と最後の投稿が重ならないようにする余白
      SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
    ];
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
                  state.items.length +
                  (state.isLoading || state.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == state.items.length) {
                  return state.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox.shrink();
                }
                final f = state.items[i];
                return _FollowUserTile(
                  key: ValueKey(f.id),
                  user: f.user,
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
    super.key,
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
      final confirmed = await confirmAction(
        context,
        ref,
        title: 'フォローを解除',
        message: 'フォローを解除してもよろしいですか？',
        confirmLabel: '解除',
      );
      if (!confirmed) return;
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
    // note: isViewingOwnFollowers was unused and removed

    return ListTile(
      onTap: () => Navigator.pop(context, widget.user.id),
      leading: UserAvatar(avatarUrl: widget.user.avatarUrl),
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
      final confirmed = await confirmAction(
        context,
        ref,
        title: 'フォローを解除',
        message: 'フォローを解除してもよろしいですか？',
        confirmLabel: '解除',
      );
      if (!confirmed) return;
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
    for (final e in _fields) {
      e.dispose();
    }
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

  /// 固定表示される領域そのものの位置を、呼び出し側から実測するためのキー。
  final Key? headerKey;

  _TabBarDelegate(this.tabBar, {this.headerKey});

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
      key: headerKey,
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
