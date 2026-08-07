import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/cache_service.dart';
import '../../../data/models/drive_file_model.dart';
import '../../../data/models/note_model.dart';
import '../../../data/models/page_model.dart';
import '../../../data/remote/misskey_api.dart';
import '../../../shared/utils/emoji_utils.dart';
import '../../../shared/widgets/image_viewer_screen.dart';
import '../../../shared/widgets/mfm_content.dart';
import '../../timeline/widgets/note_card.dart';

/// ブロックの入れ子を描画する最大の深さ。
///
/// `section` は仕様上いくらでもネストできるため、
/// 壊れたデータや悪意あるデータで描画が破綻しないよう打ち切る。
const int kPageBlockMaxDepth = 5;

/// 埋め込みノート（`note` ブロック）の取得結果を1ページ内で共有するキャッシュ。
///
/// `note` ブロックは noteId しか持たないためブロックごとに `notes/show` が走る。
/// 同じノートを複数回埋め込んでも取得は1回で済むよう、Future 自体を保持する。
class PageNoteCache {
  final MisskeyApi _api;
  final Map<String, Future<NoteModel?>> _futures = {};

  PageNoteCache(this._api);

  /// 取得できなかった場合（削除済み・非公開・権限不足）は null を返す。
  Future<NoteModel?> load(String noteId) {
    return _futures.putIfAbsent(noteId, () async {
      try {
        return await _api.getNote(noteId);
      } catch (_) {
        return null;
      }
    });
  }
}

/// ブロックレンダラに渡す描画設定。
class PageRenderConfig {
  /// `image` ブロックの `fileId` を解決するためのマップ（[PageModel.fileById]）。
  final Map<String, DriveFileModel> fileById;
  final EmojiResolver emojiResolver;

  /// 埋め込みノートのキャッシュ。null のときノートブロックは取得を行わない。
  final PageNoteCache? noteCache;

  final bool alignCenter;

  /// `serif` または `sans-serif`。
  final String font;
  final double fontSize;

  const PageRenderConfig({
    this.fileById = const {},
    this.emojiResolver = EmojiResolver.empty,
    this.noteCache,
    this.alignCenter = false,
    this.font = 'sans-serif',
    this.fontSize = 14.0,
  });

  /// `font` に対応する Flutter のフォントファミリ。
  /// `sans-serif` はテーマ既定（Noto Sans JP）に任せるため null を返す。
  String? get fontFamily => font == 'serif' ? 'serif' : null;

  Alignment get alignment =>
      alignCenter ? Alignment.center : Alignment.centerLeft;

  CrossAxisAlignment get crossAxisAlignment =>
      alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;
}

/// ブロック配列を縦に並べて描画する。
class PageBlockList extends StatelessWidget {
  final List<PageBlock> blocks;
  final PageRenderConfig config;
  final int depth;

  const PageBlockList({
    super.key,
    required this.blocks,
    required this.config,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: config.crossAxisAlignment,
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: PageBlockView(
              key: ValueKey(block.id),
              block: block,
              config: config,
              depth: depth,
            ),
          ),
      ],
    );
  }
}

/// ページの1ブロックを描画する。`section` は [depth] を増やして再帰する。
class PageBlockView extends StatelessWidget {
  final PageBlock block;
  final PageRenderConfig config;
  final int depth;

  const PageBlockView({
    super.key,
    required this.block,
    required this.config,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      PageTextBlock(:final text) => _buildText(context, text),
      PageSectionBlock b => _buildSection(context, b),
      PageImageBlock(:final fileId) => _buildImage(context, fileId),
      PageNoteBlock(:final noteId) => _buildNote(context, noteId),
      PageUnknownBlock() => _buildUnknown(context),
    };
  }

  Widget _buildText(BuildContext context, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: config.alignment,
      child: MfmContent(
        text: text,
        emojiResolver: config.emojiResolver,
        style: TextStyle(
          fontSize: config.fontSize,
          fontFamily: config.fontFamily,
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, PageSectionBlock section) {
    final theme = Theme.of(context);
    // 深さ上限に達したら中身を描画せず打ち切る（section は無限にネストできるため）
    final truncated = depth + 1 >= kPageBlockMaxDepth;
    // 深い見出しほど小さくする
    final titleSize = (config.fontSize + 8 - depth * 2).clamp(
      config.fontSize,
      config.fontSize + 8,
    );

    return Column(
      crossAxisAlignment: config.crossAxisAlignment,
      children: [
        if (section.title.trim().isNotEmpty)
          Align(
            alignment: config.alignment,
            child: MfmContent(
              text: section.title,
              emojiResolver: config.emojiResolver,
              style: TextStyle(
                fontSize: titleSize.toDouble(),
                fontWeight: FontWeight.bold,
                fontFamily: config.fontFamily,
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (truncated)
          _Placeholder(icon: Icons.unfold_less, message: 'これ以上深い階層は表示できません')
        else
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            child: PageBlockList(
              blocks: section.children,
              config: config,
              depth: depth + 1,
            ),
          ),
      ],
    );
  }

  Widget _buildImage(BuildContext context, String? fileId) {
    final file = fileId == null ? null : config.fileById[fileId];
    if (file == null) {
      // attachedFiles に無い＝ドライブから削除された等。必ずフォールバックを出す。
      return _Placeholder(
        icon: Icons.broken_image_outlined,
        message: '画像を表示できません（削除された可能性があります）',
      );
    }
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        cacheManager: AppCacheManager(),
        imageUrl: file.url,
        fit: BoxFit.contain,
        placeholder: (_, _) => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, _, _) => _Placeholder(
          icon: Icons.broken_image_outlined,
          message: '画像の読み込みに失敗しました',
        ),
      ),
    );
    return Align(
      alignment: config.alignment,
      child: GestureDetector(
        onTap: () => _openFullscreen(context, file),
        child: image,
      ),
    );
  }

  void _openFullscreen(BuildContext context, DriveFileModel file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(files: [file], title: file.name),
      ),
    );
  }

  Widget _buildNote(BuildContext context, String? noteId) {
    final cache = config.noteCache;
    if (noteId == null || noteId.isEmpty || cache == null) {
      return _Placeholder(icon: Icons.article_outlined, message: 'ノートを表示できません');
    }
    return _EmbeddedNote(noteId: noteId, cache: cache);
  }

  Widget _buildUnknown(BuildContext context) {
    return _Placeholder(
      icon: Icons.help_outline,
      message: 'このブロックは表示できません（${block.type.isEmpty ? '不明' : block.type}）',
    );
  }
}

/// 埋め込みノート。取得は [PageNoteCache] 経由なので同一ページ内で重複しない。
class _EmbeddedNote extends StatefulWidget {
  final String noteId;
  final PageNoteCache cache;

  const _EmbeddedNote({required this.noteId, required this.cache});

  @override
  State<_EmbeddedNote> createState() => _EmbeddedNoteState();
}

class _EmbeddedNoteState extends State<_EmbeddedNote> {
  late Future<NoteModel?> _future = widget.cache.load(widget.noteId);

  @override
  void didUpdateWidget(covariant _EmbeddedNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    // キャッシュが作り直された（＝ページを再読み込みした）ときも取り直す
    if (oldWidget.noteId != widget.noteId ||
        !identical(oldWidget.cache, widget.cache)) {
      _future = widget.cache.load(widget.noteId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<NoteModel?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final note = snapshot.data;
        if (note == null) {
          return _Placeholder(
            icon: Icons.visibility_off_outlined,
            message: 'ノートを取得できませんでした（削除済みか非公開の可能性があります）',
          );
        }
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: NoteCard(note: note),
        );
      },
    );
  }
}

/// 表示できないブロックの共通プレースホルダ。
class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String message;

  const _Placeholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
