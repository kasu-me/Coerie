import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/cache_service.dart';
import '../../data/models/draft_local_file_model.dart';
import '../../data/models/draft_model.dart';
import '../../data/models/drive_file_model.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'draft_provider.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/utils/media_type_utils.dart';
import '../../shared/utils/visibility_utils.dart';

/// 下書き一覧のサムネイルに出す添付。Drive のファイルと未アップロードの
/// ローカルファイルを同じリストに並べるための型。
sealed class _DraftAttachment {
  const _DraftAttachment();
}

class _DriveAttachment extends _DraftAttachment {
  final DriveFileModel file;
  const _DriveAttachment(this.file);
}

class _LocalAttachment extends _DraftAttachment {
  final DraftLocalFileModel file;
  const _LocalAttachment(this.file);
}

/// 保存時の並び順（[DraftLocalFileModel.position]）のまま1本のリストに復元する。
///
/// 並びが compose 側とずれると一覧とエディタで見え方が食い違うため、
/// compose_screen.dart の _restoreAttachedMedia と同じ手順で組み立てる。
List<_DraftAttachment> _mergedAttachments(DraftModel draft) {
  final result = draft.files
      .map<_DraftAttachment>(_DriveAttachment.new)
      .toList();
  final locals = draft.localFiles.toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final local in locals) {
    if (local.position < 0 || local.position > result.length) {
      result.add(_LocalAttachment(local));
    } else {
      result.insert(local.position, _LocalAttachment(local));
    }
  }
  return result;
}

/// 一覧のサムネイル一辺（論理px）。
const double _thumbnailSize = 48;

/// アイコンのみのプレースホルダ（動画/音声/その他/破損/NSFW共通）。
class _ThumbnailPlaceholder extends StatelessWidget {
  final IconData icon;
  const _ThumbnailPlaceholder(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  final _DraftAttachment attachment;
  const _AttachmentThumbnail(this.attachment);

  @override
  Widget build(BuildContext context) {
    Widget content;
    final a = attachment;
    if (a is _DriveAttachment) {
      final file = a.file;
      if (file.isSensitive) {
        content = const _ThumbnailPlaceholder(Icons.visibility_off);
      } else if (file.isImage) {
        content = CachedNetworkImage(
          cacheManager: AppCacheManager(),
          imageUrl: file.thumbnailUrl ?? file.url,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, _, _) =>
              const _ThumbnailPlaceholder(Icons.broken_image),
        );
      } else if (file.isVideo) {
        content = const _ThumbnailPlaceholder(Icons.videocam);
      } else if (file.isAudio) {
        content = const _ThumbnailPlaceholder(Icons.audiotrack);
      } else {
        content = const _ThumbnailPlaceholder(Icons.insert_drive_file);
      }
    } else {
      final local = (a as _LocalAttachment).file;
      // 一覧描画時に下書きを書き換えてはいけないため、実体消失はここでは
      // プレースホルダ表示のみに留める（除去は下書きを開いたときに行う）。
      if (!File(local.path).existsSync()) {
        content = const _ThumbnailPlaceholder(Icons.broken_image);
      } else if (local.isSensitive) {
        content = const _ThumbnailPlaceholder(Icons.visibility_off);
      } else if (isImagePath(local.path)) {
        content = Image.file(
          File(local.path),
          fit: BoxFit.cover,
          // 端末の写真は数千pxあり、原寸でデコードすると一覧をスクロール
          // しただけでメモリを食い潰す。高解像度端末を見込んで論理pxの3倍。
          cacheWidth: (_thumbnailSize * 3).round(),
          errorBuilder: (_, _, _) =>
              const _ThumbnailPlaceholder(Icons.broken_image),
        );
      } else if (isVideoPath(local.path)) {
        content = const _ThumbnailPlaceholder(Icons.videocam);
      } else if (isAudioPath(local.path)) {
        content = const _ThumbnailPlaceholder(Icons.audiotrack);
      } else {
        content = const _ThumbnailPlaceholder(Icons.insert_drive_file);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _thumbnailSize,
        height: _thumbnailSize,
        child: content,
      ),
    );
  }
}

/// 一覧の左端に出す添付のサムネイル。
///
/// 本文より先に「何が付いているか」を見せたいので leading に置く。複数枚を
/// 並べると本文の幅を削るため、先頭の1枚だけを出して残りは枚数で示す。
class _DraftLeadingThumbnail extends StatelessWidget {
  final List<_DraftAttachment> attachments;
  const _DraftLeadingThumbnail(this.attachments);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = attachments.length - 1;

    return SizedBox(
      width: _thumbnailSize,
      height: _thumbnailSize,
      child: Stack(
        children: [
          _AttachmentThumbnail(attachments.first),
          if (remaining > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  '+$remaining',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DraftScreen extends ConsumerWidget {
  const DraftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('下書き')),
      body: drafts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  const Text('保存された下書きはありません'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                final attachments = _mergedAttachments(draft);
                return Dismissible(
                  key: Key(draft.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) => confirmAction(
                    context,
                    ref,
                    title: '下書きを削除',
                    message: 'この下書きを削除しますか？',
                    confirmLabel: '削除',
                  ),
                  onDismissed: (_) =>
                      ref.read(draftProvider.notifier).deleteDraft(draft.id),
                  child: ListTile(
                    leading: attachments.isEmpty
                        ? null
                        : _DraftLeadingThumbnail(attachments),
                    title: draft.text.trim().isEmpty
                        ? Text(
                            '（本文なし）',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          )
                        : Text(
                            draft.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    subtitle: Row(
                      children: [
                        Icon(
                          visibilityIcon(draft.visibility),
                          size: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppConstants.visibilityLabels[draft.visibility] ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatYmdHm(draft.savedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: () {
                      context.pop();
                      context.push('/compose?draftId=${draft.id}');
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          ref,
                          title: '下書きを削除',
                          message: 'この下書きを削除しますか？',
                          confirmLabel: '削除',
                        );
                        if (confirmed) {
                          ref
                              .read(draftProvider.notifier)
                              .deleteDraft(draft.id);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
