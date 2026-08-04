import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/services/cache_service.dart';
import '../../../data/models/page_model.dart';
import '../../../shared/utils/format_utils.dart';

/// ページ一覧の1行。アイキャッチ・タイトル・概要・いいね数を表示する。
class PageListTile extends StatelessWidget {
  final PageModel page;

  /// タップ時の遷移先を差し替えたい場合に指定する。既定は `/pages/:pageId`。
  final VoidCallback? onTap;

  const PageListTile({super.key, required this.page, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = page.user;
    final subtitleParts = <String>[
      if (author != null) author.acct,
      formatYmd(page.updatedAt),
    ];

    return ListTile(
      leading: _Thumbnail(page: page),
      title: Text(
        page.title.isEmpty ? '(無題)' : page.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((page.summary ?? '').trim().isNotEmpty)
            Text(
              page.summary!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            subtitleParts.join(' ・ '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      isThreeLine: (page.summary ?? '').trim().isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            (page.isLiked ?? false) ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: (page.isLiked ?? false)
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          Text(
            '${page.likedCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      onTap: onTap ?? () => context.push('/pages/${page.id}', extra: page),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PageModel page;

  const _Thumbnail({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = page.eyeCatchingImage?.url;
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: url == null
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.outline,
                ),
              )
            : CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
      ),
    );
  }
}

/// ページ系画面で共通のエラー表示。
///
/// 権限スコープ不足のときは再認証（アカウント設定）への導線も出す。
class PagesErrorView extends StatelessWidget {
  /// 生の例外。null のときは [message] だけを表示する。
  final Object? error;
  final String message;
  final VoidCallback onRetry;

  const PagesErrorView({
    super.key,
    this.error,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsReauth = error != null && isPermissionError(error!);
    final text = error != null
        ? apiErrorMessage(error!, fallback: message)
        : message;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                  onPressed: onRetry,
                ),
                if (needsReauth)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('再認証'),
                    onPressed: () => context.push('/account-settings'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ページが1件もないときの共通表示（Pull-to-Refresh 可能）。
class PagesEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onRefresh;

  const PagesEmptyView({
    super.key,
    this.icon = Icons.description_outlined,
    required this.title,
    required this.description,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(title),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
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
