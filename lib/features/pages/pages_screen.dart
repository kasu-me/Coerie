import '../../shared/mixins/infinite_scroll_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/page_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/paged_notifier.dart';
import 'providers/pages_provider.dart';
import 'widgets/page_list_tile.dart';

/// ページ一覧画面（`/pages`）。
///
/// タブ構成は「自分のページ（`i/pages`）/ いいね（`i/page-likes`）/
/// おすすめ（`pages/featured`）」。おすすめは引数なし固定10件のため
/// 無限スクロールは行わず、読み切り＋Pull-to-Refresh で扱う。
class PagesScreen extends ConsumerStatefulWidget {
  const PagesScreen({super.key});

  @override
  ConsumerState<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends ConsumerState<PagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  )..addListener(_onTabChanged);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// タブによって FAB の表示可否が変わるため再ビルドする。
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  String get _accountKey => ref.read(activeAccountProvider)?.id ?? '';

  Future<void> _openEditor() async {
    await context.push('/pages/new');
    if (!mounted) return;
    ref.read(myPagesProvider(_accountKey).notifier).refresh();
  }

  void _refreshCurrent() {
    final key = _accountKey;
    switch (_tabController.index) {
      case 0:
        ref.read(myPagesProvider(key).notifier).refresh();
      case 1:
        ref.read(likedPagesProvider(key).notifier).refresh();
      default:
        ref.invalidate(featuredPagesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountKey = ref.watch(activeAccountProvider)?.id ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('ページ'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: 'マイページ'),
            Tab(icon: Icon(Icons.favorite_border), text: 'いいね'),
            Tab(icon: Icon(Icons.local_fire_department_outlined), text: 'おすすめ'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: _refreshCurrent,
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('作成'),
            )
          : null,
      body: SafeArea(
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          children: [
            _MyPagesTab(accountKey: accountKey),
            _LikedPagesTab(accountKey: accountKey),
            const _FeaturedPagesTab(),
          ],
        ),
      ),
    );
  }
}

// ---- 自分のページ ----

class _MyPagesTab extends ConsumerWidget {
  final String accountKey;

  const _MyPagesTab({required this.accountKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myPagesProvider(accountKey));
    final notifier = ref.read(myPagesProvider(accountKey).notifier);
    return PagedPagesList<PageModel>(
      state: state,
      rawError: notifier.lastError,
      errorFallback: 'ページの取得に失敗しました',
      onRefresh: notifier.refresh,
      onLoadMore: () => notifier.fetch(loadMore: true),
      itemBuilder: (page) => PageListTile(page: page),
      emptyBuilder: (onRefresh) => PagesEmptyView(
        title: 'ページがありません',
        description: '右下の「作成」ボタンから新しいページを作れます',
        onRefresh: onRefresh,
      ),
    );
  }
}

// ---- いいねしたページ ----

class _LikedPagesTab extends ConsumerWidget {
  final String accountKey;

  const _LikedPagesTab({required this.accountKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(likedPagesProvider(accountKey));
    final notifier = ref.read(likedPagesProvider(accountKey).notifier);
    return PagedPagesList<PageLikeModel>(
      state: state,
      rawError: notifier.lastError,
      errorFallback: 'いいねしたページの取得に失敗しました',
      onRefresh: notifier.refresh,
      onLoadMore: () => notifier.fetch(loadMore: true),
      itemBuilder: (like) => PageListTile(page: like.page),
      emptyBuilder: (onRefresh) => PagesEmptyView(
        icon: Icons.favorite_border,
        title: 'いいねしたページがありません',
        description: 'ページの ♡ ボタンでいいねできます',
        onRefresh: onRefresh,
      ),
    );
  }
}

// ---- おすすめ ----

class _FeaturedPagesTab extends ConsumerWidget {
  const _FeaturedPagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(featuredPagesProvider);
    Future<void> refresh() async {
      ref.invalidate(featuredPagesProvider);
      await ref.read(featuredPagesProvider.future);
    }

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => PagesErrorView(
        error: e,
        message: 'おすすめページの取得に失敗しました',
        onRetry: () => ref.invalidate(featuredPagesProvider),
      ),
      data: (pages) {
        if (pages.isEmpty) {
          return PagesEmptyView(
            icon: Icons.local_fire_department_outlined,
            title: 'おすすめのページがありません',
            description: 'このサーバーにはまだ人気のページがないようです',
            onRefresh: refresh,
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: pages.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => PageListTile(page: pages[i]),
          ),
        );
      },
    );
  }
}

// ---- 無限スクロール共通リスト ----

/// [PagedNotifier] の状態を表示する共通リスト。
/// 末尾付近までスクロールしたら [onLoadMore] を呼ぶ。
class PagedPagesList<T> extends StatefulWidget {
  final PagedState<T> state;

  /// `showApiErrorSnackBar` / `apiErrorMessage` に渡す生の例外。
  final Object? rawError;
  final String errorFallback;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Widget Function(T item) itemBuilder;
  final Widget Function(Future<void> Function() onRefresh) emptyBuilder;

  const PagedPagesList({
    super.key,
    required this.state,
    required this.errorFallback,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.emptyBuilder,
    this.rawError,
  });

  @override
  State<PagedPagesList<T>> createState() => _PagedPagesListState<T>();
}

class _PagedPagesListState<T> extends State<PagedPagesList<T>>
    with InfiniteScrollMixin<PagedPagesList<T>> {
  @override
  void onLoadMore() {
    if (widget.state.isLoading || !widget.state.hasMore) return;
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return PagesErrorView(
        error: widget.rawError,
        message: widget.errorFallback,
        onRetry: widget.onRefresh,
      );
    }
    if (state.items.isEmpty) return widget.emptyBuilder(widget.onRefresh);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return widget.itemBuilder(state.items[i]);
        },
      ),
    );
  }
}
