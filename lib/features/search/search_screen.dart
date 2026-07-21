import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';
import '../timeline/widgets/note_card.dart';
import 'search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final int initialTab;
  final String? initialQuery;

  const SearchScreen({super.key, this.initialTab = 0, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // 検索対象タブを切り替えても入力内容が消えないよう、入力欄は全タブで共有する
  final _queryController = TextEditingController();

  static const _hintTexts = [
    'キーワードでノートを検索',
    'ハッシュタグでノートを検索（# 不要）',
    'ユーザー名・表示名で検索',
    'ハッシュタグを検索（# 不要）',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _tabController.addListener(_onTabChanged);
    _queryController.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 画面表示時に必ず状態をリセット
      ref.read(noteSearchProvider.notifier).clear();
      ref.read(tagNoteSearchProvider.notifier).clear();
      ref.read(userSearchProvider.notifier).clear();
      ref.read(hashtagSearchProvider.notifier).clear();

      // 初期クエリがある場合はタブに応じて自動検索
      if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
        _queryController.text = widget.initialQuery!;
        _search();
      }
    });
  }

  void _onTabChanged() => setState(() {});
  void _onQueryChanged() => setState(() {});

  /// 現在のタブに対応するプロバイダーで検索を実行する
  void _search() {
    final query = _queryController.text;
    switch (_tabController.index) {
      case 0:
        // ノート検索がサーバーで無効な場合は何もしない（initialQuery 自動検索のガードも兼ねる）
        final canSearchNotes =
            ref.read(canSearchNotesProvider).valueOrNull ?? true;
        if (canSearchNotes) {
          ref.read(noteSearchProvider.notifier).search(query);
        }
      case 1:
        ref.read(tagNoteSearchProvider.notifier).search(query);
      case 2:
        ref.read(userSearchProvider.notifier).search(query);
      case 3:
        ref.read(hashtagSearchProvider.notifier).search(query);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _queryController.removeListener(_onQueryChanged);
    _tabController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSearchNotes = ref.watch(canSearchNotesProvider).valueOrNull ?? true;
    // ノートタブでのみ、サーバー側でノート検索が無効な場合に検索操作を封じる
    final searchBarEnabled = !(_tabController.index == 0 && !canSearchNotes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('検索'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(text: 'ノート'),
            Tab(text: 'タグ'),
            Tab(text: 'ユーザー'),
            Tab(text: 'ハッシュタグ'),
          ],
        ),
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _queryController,
            hintText: _hintTexts[_tabController.index],
            onSearch: _search,
            enabled: searchBarEnabled,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _NoteSearchTab(onRetry: _search),
                _TagNoteSearchTab(onRetry: _search),
                _UserSearchTab(onRetry: _search),
                _HashtagSearchTab(onRetry: _search),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
          _tabController.index == 1 && _queryController.text.trim().isNotEmpty
          ? FloatingActionButton(
              onPressed: () {
                final tag = _queryController.text.trim();
                context.push('/compose', extra: {'initialText': '#$tag '});
              },
              tooltip: '#${_queryController.text.trim()} で投稿',
              child: const Icon(Icons.edit),
            )
          : null,
    );
  }
}

// ---- 共通ウィジェット ----

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSearch;
  // サーバー側で検索機能が無効な場合に検索ボタン・Enter送信を封じるためのフラグ
  final bool enabled;

  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onSearch,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: enabled ? (_) => onSearch() : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: enabled ? onSearch : null, child: const Text('検索')),
        ],
      ),
    );
  }
}

Widget _buildErrorWidget(
  BuildContext context,
  SearchError error,
  VoidCallback onRetry,
) {
  final isDisabled = error.type == SearchErrorType.disabled;
  return _buildStatusWidget(
    context,
    icon: isDisabled ? Icons.block : Icons.wifi_off,
    message: isDisabled ? 'この機能はサーバーで無効になっています' : error.message,
    onRetry: isDisabled ? null : onRetry,
  );
}

/// サーバー側で機能自体が無効と事前判明している場合の案内表示。
/// 事後エラー（_buildErrorWidget）と同じ見た目だが、再試行しても無意味なため
/// 再試行ボタンは表示しない。
Widget _buildDisabledWidget(BuildContext context, String message) {
  return _buildStatusWidget(context, icon: Icons.block, message: message);
}

Widget _buildStatusWidget(
  BuildContext context, {
  required IconData icon,
  required String message,
  VoidCallback? onRetry,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---- ノート検索タブ ----

class _NoteSearchTab extends ConsumerStatefulWidget {
  final VoidCallback onRetry;

  const _NoteSearchTab({required this.onRetry});

  @override
  ConsumerState<_NoteSearchTab> createState() => _NoteSearchTabState();
}

class _NoteSearchTabState extends ConsumerState<_NoteSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  // 新規検索（loadMore ではない）を検知したら、結果反映後にスクロール位置を
  // 先頭へ戻すためのフラグ。これをしないと前回結果を下までスクロールした
  // オフセットが新結果に引き継がれ最下部にクランプされ、無限スクロールが
  // 発火しなくなる。
  bool _pendingScrollReset = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 稀に ScrollController が複数の ScrollPosition に紐づくと `.position` が
    // 例外を投げ、以降 loadMore に到達しなくなるため安全に判定する（本来は 1 個）。
    if (_scrollController.positions.length != 1) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(noteSearchProvider.notifier).loadMore();
    }
  }

  /// 新規検索の開始→結果反映を監視し、結果が入った直後に先頭へスクロールを戻す。
  void _handleScrollReset(NoteSearchState? prev, NoteSearchState next) {
    final startedFresh =
        next.isLoading &&
        next.notes.isEmpty &&
        !(prev != null && prev.isLoading && prev.notes.isEmpty);
    if (startedFresh) _pendingScrollReset = true;
    final gotResults = !next.isLoading && next.notes.isNotEmpty;
    if (gotResults && _pendingScrollReset) {
      _pendingScrollReset = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(noteSearchProvider, _handleScrollReset);
    final state = ref.watch(noteSearchProvider);
    final canSearchNotes = ref.watch(canSearchNotesProvider).valueOrNull ?? true;
    if (!canSearchNotes) {
      // サーバー側で無効と事前判明している場合は、期間フィルタも含めて
      // 操作しても無意味な要素は表示せず案内のみ表示する
      return _buildDisabledWidget(context, 'ノート検索はこのサーバーで無効になっています');
    }
    // 検索対象セレクタ・期間フィルタ行は常にリスト上部に表示し、
    // 本文は状態に応じて切り替える
    return Column(
      children: [
        const _NoteScopeSelector(),
        _DateRangeFilter(
          rangeStart: state.rangeStart,
          rangeEnd: state.rangeEnd,
        ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(NoteSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(context, state.error!, widget.onRetry);
    }
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.notes.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するノートが見つかりませんでした'));
    }
    if (state.notes.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return _NoteList(
      notes: state.notes,
      isLoadingMore: state.isLoading,
      scrollController: _scrollController,
      onRefresh: () => ref.read(noteSearchProvider.notifier).refresh(),
    );
  }
}

// ---- 検索対象セレクタ（ノート検索専用）----

class _NoteScopeSelector extends ConsumerStatefulWidget {
  const _NoteScopeSelector();

  @override
  ConsumerState<_NoteScopeSelector> createState() => _NoteScopeSelectorState();
}

class _NoteScopeSelectorState extends ConsumerState<_NoteScopeSelector> {
  late final TextEditingController _hostController;
  late final TextEditingController _userController;

  static const _scopes = [
    (NoteSearchScope.all, '全て'),
    (NoteSearchScope.local, 'ローカル'),
    (NoteSearchScope.server, 'サーバ指定'),
    (NoteSearchScope.user, 'ユーザー指定'),
  ];

  @override
  void initState() {
    super.initState();
    // 保持されている検索対象の入力内容を初期表示する
    final state = ref.read(noteSearchProvider);
    _hostController = TextEditingController(text: state.host);
    _userController = TextEditingController(text: state.userAcct);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _userController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(noteSearchProvider.select((s) => s.scope));
    final notifier = ref.read(noteSearchProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _scopes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.$2),
                      selected: scope == s.$1,
                      onSelected: (_) => notifier.setScope(s.$1),
                    ),
                  ),
              ],
            ),
          ),
          if (scope == NoteSearchScope.server)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  hintText: '対象サーバーのホスト名（例: misskey.io）',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: notifier.setScopeHost,
                textInputAction: TextInputAction.search,
              ),
            ),
          if (scope == NoteSearchScope.user)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  hintText: '対象ユーザー（例: @name または @name@example.com）',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: notifier.setScopeUserAcct,
                textInputAction: TextInputAction.search,
              ),
            ),
        ],
      ),
    );
  }
}

// ---- 期間フィルタ（ノート検索専用）----

class _DateRangeFilter extends ConsumerWidget {
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  const _DateRangeFilter({this.rangeStart, this.rangeEnd});

  /// yyyy/MM/dd 形式に手組みで整形する（intl はプロジェクト直接依存ではないため）
  String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y/$m/$day';
  }

  /// 期間ピッカーを開き、確定した範囲をプロバイダーへ反映する
  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initialRange = (rangeStart != null && rangeEnd != null)
        ? DateTimeRange(start: rangeStart!, end: rangeEnd!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: initialRange,
    );
    if (picked != null) {
      ref
          .read(noteSearchProvider.notifier)
          .setDateRange(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRange = rangeStart != null && rangeEnd != null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: hasRange
            ? InputChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(
                  '${_formatDate(rangeStart!)} 〜 ${_formatDate(rangeEnd!)}',
                ),
                onPressed: () => _pickRange(context, ref),
                onDeleted: () => ref
                    .read(noteSearchProvider.notifier)
                    .setDateRange(null, null),
                deleteIcon: const Icon(Icons.close, size: 18),
                deleteButtonTooltipMessage: '期間を解除',
              )
            : ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: const Text('期間を指定'),
                onPressed: () => _pickRange(context, ref),
              ),
      ),
    );
  }
}

// ---- タグ検索タブ ----

class _TagNoteSearchTab extends ConsumerStatefulWidget {
  final VoidCallback onRetry;

  const _TagNoteSearchTab({required this.onRetry});

  @override
  ConsumerState<_TagNoteSearchTab> createState() => _TagNoteSearchTabState();
}

class _TagNoteSearchTabState extends ConsumerState<_TagNoteSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(tagNoteSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(tagNoteSearchProvider);
    return _buildBody(state);
  }

  Widget _buildBody(TagNoteSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(context, state.error!, widget.onRetry);
    }
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.notes.isEmpty && state.tag.isNotEmpty) {
      return const Center(child: Text('該当するノートが見つかりませんでした'));
    }
    if (state.notes.isEmpty) {
      return const Center(
        child: Text('タグを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return _NoteList(
      notes: state.notes,
      isLoadingMore: state.isLoading,
      scrollController: _scrollController,
      onRefresh: () => ref.read(tagNoteSearchProvider.notifier).refresh(),
    );
  }
}

// ---- ユーザー検索タブ ----

class _UserSearchTab extends ConsumerStatefulWidget {
  final VoidCallback onRetry;

  const _UserSearchTab({required this.onRetry});

  @override
  ConsumerState<_UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends ConsumerState<_UserSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  // 新規検索の結果反映後に先頭へスクロールを戻すためのフラグ（_NoteSearchTab と同様）
  bool _pendingScrollReset = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 同上（複数ポジション時の例外を防ぐ）。
    if (_scrollController.positions.length != 1) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(userSearchProvider.notifier).loadMore();
    }
  }

  /// 新規検索の開始→結果反映を監視し、結果が入った直後に先頭へスクロールを戻す。
  void _handleScrollReset(UserSearchState? prev, UserSearchState next) {
    final startedFresh =
        next.isLoading &&
        next.users.isEmpty &&
        !(prev != null && prev.isLoading && prev.users.isEmpty);
    if (startedFresh) _pendingScrollReset = true;
    final gotResults = !next.isLoading && next.users.isNotEmpty;
    if (gotResults && _pendingScrollReset) {
      _pendingScrollReset = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(userSearchProvider, _handleScrollReset);
    final state = ref.watch(userSearchProvider);
    return Column(
      children: [
        const _UserOriginSelector(),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(UserSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(context, state.error!, widget.onRetry);
    }
    if (state.isLoading && state.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.users.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するユーザーが見つかりませんでした'));
    }
    if (state.users.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(userSearchProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.users.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.users.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _UserTile(user: state.users[index]);
        },
      ),
    );
  }
}

// ---- 検索対象セレクタ（ユーザー検索専用）----

class _UserOriginSelector extends ConsumerWidget {
  const _UserOriginSelector();

  static const _origins = [
    (UserSearchOrigin.all, '全て'),
    (UserSearchOrigin.local, 'ローカル'),
    (UserSearchOrigin.remote, 'リモート'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(userSearchProvider.select((s) => s.origin));
    final notifier = ref.read(userSearchProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final o in _origins)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(o.$2),
                  selected: origin == o.$1,
                  onSelected: (_) => notifier.setOrigin(o.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;

  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(
                user.avatarUrl!,
                cacheManager: AppCacheManager(),
              )
            : null,
        child: user.avatarUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(user.acct, overflow: TextOverflow.ellipsis),
      onTap: () => context.push('/profile/${user.id}'),
    );
  }
}

// ---- ハッシュタグ検索タブ ----

class _HashtagSearchTab extends ConsumerStatefulWidget {
  final VoidCallback onRetry;

  const _HashtagSearchTab({required this.onRetry});

  @override
  ConsumerState<_HashtagSearchTab> createState() => _HashtagSearchTabState();
}

class _HashtagSearchTabState extends ConsumerState<_HashtagSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(hashtagSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(hashtagSearchProvider);
    return _buildBody(state);
  }

  Widget _buildBody(HashtagSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(context, state.error!, widget.onRetry);
    }
    if (state.isLoading && state.hashtags.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.hashtags.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するハッシュタグが見つかりませんでした'));
    }
    if (state.hashtags.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(hashtagSearchProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.hashtags.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.hashtags.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final tag = state.hashtags[index];
          return ListTile(
            leading: const Icon(Icons.tag),
            title: Text('#$tag'),
            onTap: () {
              // タグタブに遷移してそのタグで検索
              // SearchScreen の TabController を操作する方法として
              // タグタブ（index=1）にフォーカスして自動検索するために
              // go_router の extra で情報を渡す
              context.push('/search', extra: {'tab': 1, 'query': tag});
            },
          );
        },
      ),
    );
  }
}

// ---- 共通ノートリスト ----

class _NoteList extends StatelessWidget {
  final List<NoteModel> notes;
  final bool isLoadingMore;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;

  const _NoteList({
    required this.notes,
    required this.isLoadingMore,
    required this.scrollController,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: notes.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == notes.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return NoteCard(note: notes[index]);
        },
      ),
    );
  }
}
