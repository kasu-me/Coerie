import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/cache_service.dart';
import '../../../data/models/draft_local_file_model.dart';
import '../../../data/models/drive_file_model.dart';
import '../../../shared/utils/media_type_utils.dart';

// 端末の下書き一覧と予約投稿一覧で添付の見せ方を揃えるため、両画面で共有している。

/// 下書き一覧のサムネイルに出す添付。Drive のファイルと未アップロードの
/// ローカルファイルを同じリストに並べるための型。
sealed class DraftAttachment {
  const DraftAttachment();
}

class DriveDraftAttachment extends DraftAttachment {
  final DriveFileModel file;
  const DriveDraftAttachment(this.file);
}

class LocalDraftAttachment extends DraftAttachment {
  final DraftLocalFileModel file;
  const LocalDraftAttachment(this.file);
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
  final DraftAttachment attachment;
  const _AttachmentThumbnail(this.attachment);

  @override
  Widget build(BuildContext context) {
    Widget content;
    final a = attachment;
    if (a is DriveDraftAttachment) {
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
      final local = (a as LocalDraftAttachment).file;
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
class DraftLeadingThumbnail extends StatelessWidget {
  final List<DraftAttachment> attachments;
  const DraftLeadingThumbnail(this.attachments, {super.key});

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
