import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/cache_service.dart';
import '../../../data/models/gallery_post_model.dart';

/// ギャラリー投稿の画像グリッド（新着・人気・おすすめ・自分の投稿・いいね・
/// ユーザー別のすべての一覧タブで共通利用する）。
class GalleryPostGrid extends StatelessWidget {
  final List<GalleryPostModel> posts;
  final bool isLoading;
  final bool hasMore;
  final ScrollController? scrollController;
  final Future<void> Function() onRefresh;
  final void Function(GalleryPostModel post) onTap;
  final String emptyTitle;
  final String emptyDescription;

  const GalleryPostGrid({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.hasMore,
    required this.onRefresh,
    required this.onTap,
    this.scrollController,
    this.emptyTitle = '投稿がありません',
    this.emptyDescription = '',
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(emptyTitle),
                    if (emptyDescription.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          emptyDescription,
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final itemCount = posts.length + (hasMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= posts.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final post = posts[index];
          return GalleryPostTile(post: post, onTap: () => onTap(post));
        },
      ),
    );
  }
}

/// グリッド1枚分のタイル。サムネイル + タイトル + いいね数 + センシティブ/複数枚バッジ。
class GalleryPostTile extends StatelessWidget {
  final GalleryPostModel post;
  final VoidCallback onTap;

  const GalleryPostTile({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbFile = post.files.isNotEmpty ? post.files.first : null;
    final thumbUrl = thumbFile?.thumbnailUrl ?? thumbFile?.url;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbUrl != null)
              CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: thumbUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: theme.colorScheme.surfaceContainerHighest),
                errorWidget: (_, _, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: theme.colorScheme.outline,
                ),
              ),
            // センシティブ判定は投稿単位。サムネイル自体はぼかさず、目印のみ表示する
            // （全画面表示にする詳細画面側で実際のぼかし＋タップ解除を行う）。
            if (post.isSensitive)
              const Positioned(
                top: 4,
                left: 4,
                child: _Badge(icon: Icons.visibility_off, label: 'センシティブ'),
              ),
            if (post.files.length > 1)
              Positioned(
                top: 4,
                right: 4,
                child: _Badge(
                  icon: Icons.collections_outlined,
                  label: '${post.files.length}',
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (post.likedCount > 0) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.favorite, color: Colors.white, size: 11),
                      const SizedBox(width: 2),
                      Text(
                        '${post.likedCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
