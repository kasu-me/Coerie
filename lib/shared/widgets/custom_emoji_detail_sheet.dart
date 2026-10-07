import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/custom_emoji_provider.dart';

/// カスタム絵文字の詳細（画像・名前・タグ）を表示するボトムシート。
///
/// [url] は本文の描画で実際に解決されたURLを渡すこと。ローカル絵文字か
/// どうかの判定に使う（[_CustomEmojiDetailSheet] 参照）。
Future<void> showCustomEmojiDetailSheet(
  BuildContext context, {
  required String name,
  required String url,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: _CustomEmojiDetailSheet(
        name: name,
        url: url,
        onCopy: () async {
          Navigator.pop(sheetCtx);
          await Clipboard.setData(ClipboardData(text: ':$name:'));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('絵文字名をコピーしました'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    ),
  );
}

class _CustomEmojiDetailSheet extends ConsumerWidget {
  final String name;
  final String url;
  final VoidCallback onCopy;

  const _CustomEmojiDetailSheet({
    required this.name,
    required this.url,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // タグ（aliases）は接続先インスタンスの絵文字一覧からしか引けない。
    // リモート投稿の絵文字はローカルに同名の別絵文字があり得るため、
    // 名前だけでなくURLまで一致したものだけをローカル絵文字とみなし、
    // それ以外はタグ欄自体を出さない（Web版もリモート絵文字の詳細は出さない）。
    final localEmoji = ref
        .watch(customEmojisProvider)
        .whenOrNull(
          data: (list) {
            for (final e in list) {
              if (e.name == name && e.url == url) return e;
            }
            return null;
          },
        );
    final tags = localEmoji?.aliases.where((a) => a.isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: url,
                height: 128,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => const SizedBox(width: 128, height: 128),
                errorWidget: (_, _, _) => const SizedBox(
                  width: 128,
                  height: 128,
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('名前', style: labelStyle),
          Row(
            children: [
              Flexible(child: Text(name, style: theme.textTheme.bodyLarge)),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: '絵文字名をコピー',
                visualDensity: VisualDensity.compact,
                onPressed: onCopy,
              ),
            ],
          ),
          if (tags != null) ...[
            const SizedBox(height: 8),
            Text('タグ', style: labelStyle),
            const SizedBox(height: 4),
            if (tags.isEmpty)
              Text('なし', style: theme.textTheme.bodyMedium)
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
