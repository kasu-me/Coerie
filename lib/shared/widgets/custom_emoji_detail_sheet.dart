import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/custom_emoji_provider.dart';

/// カスタム絵文字の詳細（画像・名前・カテゴリ・タグ）を表示するボトムシート。
///
/// [url] は呼び出し元の描画で実際に解決されたURLを渡すこと。ローカル絵文字か
/// どうかの判定に使う（[_CustomEmojiDetailSheet] 参照）。
Future<void> showCustomEmojiDetailSheet(
  BuildContext context, {
  required String name,
  required String url,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
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
          _showCopiedNotice(overlay);
        },
      ),
    ),
  );
}

/// SnackBar は呼び出し元画面の Scaffold に描画されるため、絵文字ピッカーの
/// ようなモーダルの上から詳細を開くと、ピッカーの裏に隠れて見えない。
/// どこから開いても見えるよう、ルートの Overlay に出している。
void _showCopiedNotice(OverlayState overlay) {
  if (!overlay.mounted) return;
  final entry = OverlayEntry(builder: (_) => const _CopiedNotice());
  overlay.insert(entry);
  Timer(const Duration(seconds: 1), () {
    entry.remove();
    entry.dispose();
  });
}

class _CopiedNotice extends StatelessWidget {
  const _CopiedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // ルートの Overlay には Scaffold のキーボード回避が効かない。
      // サジェストから開いた場合は、シートを閉じるとキーボードが戻ってくる。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: Semantics(
              liveRegion: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 150),
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: theme.colorScheme.inverseSurface,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text(
                        '絵文字名をコピーしました',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

    // カテゴリとタグ（aliases）は接続先インスタンスの絵文字一覧からしか引けない。
    // リモート投稿の絵文字はローカルに同名の別絵文字があり得るため、
    // 名前だけでなくURLまで一致したものだけをローカル絵文字とみなし、
    // それ以外は両欄とも出さない（Web版もリモート絵文字の詳細は出さない）。
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
          if (localEmoji != null) ...[
            const SizedBox(height: 8),
            Text('カテゴリ', style: labelStyle),
            const SizedBox(height: 4),
            Text(
              localEmoji.category.isEmpty ? '未分類' : localEmoji.category,
              style: theme.textTheme.bodyMedium,
            ),
          ],
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
