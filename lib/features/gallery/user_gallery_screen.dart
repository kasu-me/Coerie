import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/mixins/infinite_scroll_mixin.dart';
import '../../data/models/gallery_post_model.dart';
import 'providers/gallery_providers.dart';
import 'widgets/gallery_post_grid.dart';

/// 指定ユーザーのギャラリー投稿一覧（users/gallery/posts, 無限スクロール）。
class UserGalleryScreen extends ConsumerStatefulWidget {
  final String userId;
  final String? userName;

  const UserGalleryScreen({super.key, required this.userId, this.userName});

  @override
  ConsumerState<UserGalleryScreen> createState() => _UserGalleryScreenState();
}

class _UserGalleryScreenState extends ConsumerState<UserGalleryScreen>
    with InfiniteScrollMixin<UserGalleryScreen> {
  @override
  void onLoadMore() => ref
      .read(galleryUserPostsProvider(widget.userId).notifier)
      .fetch(loadMore: true);

  Future<void> _openDetail(GalleryPostModel post) async {
    final result = await context.push<GalleryDetailResult>(
      '/gallery/${post.id}',
      extra: post,
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(galleryUserPostsProvider(widget.userId).notifier);
    if (result.post != null) {
      notifier.applyUpdate(result.post!);
    } else if (result.deletedId != null) {
      notifier.removePost(result.deletedId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryUserPostsProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.userName != null ? '${widget.userName} のギャラリー' : 'ギャラリー',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () => ref
                .read(galleryUserPostsProvider(widget.userId).notifier)
                .refresh(),
          ),
        ],
      ),
      body: GalleryPostGrid(
        posts: state.items,
        isLoading: state.isLoading,
        hasMore: state.hasMore,
        scrollController: scrollController,
        onRefresh: () => ref
            .read(galleryUserPostsProvider(widget.userId).notifier)
            .refresh(),
        onTap: _openDetail,
        emptyTitle: 'ギャラリー投稿がありません',
      ),
    );
  }
}
