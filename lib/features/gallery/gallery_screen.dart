import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/gallery_post_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/paged_notifier.dart';
import 'providers/gallery_providers.dart';
import 'widgets/gallery_post_grid.dart';

/// ギャラリー一覧画面（新着 / 人気 / おすすめ / 自分の投稿 / いいね）。
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(activeAccountProvider)?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ギャラリー'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '新着'),
            Tab(text: '人気'),
            Tab(text: 'おすすめ'),
            Tab(text: '自分の投稿'),
            Tab(text: 'いいね'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/gallery/new'),
        tooltip: '投稿を作成',
        child: const Icon(Icons.add_photo_alternate_outlined),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GalleryPostsTab(
            provider: galleryNewProvider,
            accountId: accountId,
            allowLoadMore: true,
            emptyTitle: '新着の投稿がありません',
          ),
          _GalleryPostsTab(
            provider: galleryPopularProvider,
            accountId: accountId,
            allowLoadMore: false,
            emptyTitle: '人気の投稿がありません',
          ),
          _GalleryPostsTab(
            provider: galleryFeaturedProvider,
            accountId: accountId,
            allowLoadMore: true,
            emptyTitle: 'おすすめの投稿がありません',
          ),
          _GalleryPostsTab(
            provider: galleryMineProvider,
            accountId: accountId,
            allowLoadMore: true,
            emptyTitle: 'まだ投稿がありません',
            emptyDescription: '右下の + ボタンから作品を投稿できます',
          ),
          _GalleryLikedTab(accountId: accountId),
        ],
      ),
    );
  }
}

/// GalleryPostModel を扱うタブ共通実装（新着 / 人気 / おすすめ / 自分の投稿）。
class _GalleryPostsTab extends ConsumerStatefulWidget {
  final AutoDisposeStateNotifierProviderFamily<
    GalleryPostsNotifier,
    PagedState<GalleryPostModel>,
    String
  >
  provider;
  final String accountId;
  final bool allowLoadMore;
  final String emptyTitle;
  final String emptyDescription;

  const _GalleryPostsTab({
    required this.provider,
    required this.accountId,
    required this.allowLoadMore,
    required this.emptyTitle,
    this.emptyDescription = '',
  });

  @override
  ConsumerState<_GalleryPostsTab> createState() => _GalleryPostsTabState();
}

class _GalleryPostsTabState extends ConsumerState<_GalleryPostsTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.allowLoadMore) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(widget.provider(widget.accountId).notifier)
          .fetch(loadMore: true);
    }
  }

  Future<void> _openDetail(GalleryPostModel post) async {
    final result = await context.push<GalleryDetailResult>(
      '/gallery/${post.id}',
      extra: post,
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(widget.provider(widget.accountId).notifier);
    if (result.post != null) {
      notifier.applyUpdate(result.post!);
    } else if (result.deletedId != null) {
      notifier.removePost(result.deletedId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(widget.provider(widget.accountId));
    return GalleryPostGrid(
      posts: state.items,
      isLoading: state.isLoading,
      hasMore: widget.allowLoadMore && state.hasMore,
      scrollController: _scrollController,
      onRefresh: () => ref.read(widget.provider(widget.accountId).notifier).refresh(),
      onTap: _openDetail,
      emptyTitle: widget.emptyTitle,
      emptyDescription: widget.emptyDescription,
    );
  }
}

/// いいねタブ（GalleryLikeModel のラッパーを扱う）。
class _GalleryLikedTab extends ConsumerStatefulWidget {
  final String accountId;
  const _GalleryLikedTab({required this.accountId});

  @override
  ConsumerState<_GalleryLikedTab> createState() => _GalleryLikedTabState();
}

class _GalleryLikedTabState extends ConsumerState<_GalleryLikedTab>
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
      ref
          .read(galleryLikedProvider(widget.accountId).notifier)
          .fetch(loadMore: true);
    }
  }

  Future<void> _openDetail(GalleryPostModel post) async {
    final result = await context.push<GalleryDetailResult>(
      '/gallery/${post.id}',
      extra: post,
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(galleryLikedProvider(widget.accountId).notifier);
    if (result.post != null) {
      notifier.applyUpdate(result.post!);
    } else if (result.deletedId != null) {
      notifier.removePost(result.deletedId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(galleryLikedProvider(widget.accountId));
    final posts = state.items.map((e) => e.post).toList();
    return GalleryPostGrid(
      posts: posts,
      isLoading: state.isLoading,
      hasMore: state.hasMore,
      scrollController: _scrollController,
      onRefresh: () =>
          ref.read(galleryLikedProvider(widget.accountId).notifier).refresh(),
      onTap: _openDetail,
      emptyTitle: 'いいねした投稿がありません',
      emptyDescription: '投稿の ♥ ボタンでいいねできます',
    );
  }
}
