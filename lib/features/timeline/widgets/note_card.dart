import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/note_model.dart';
import '../../../shared/widgets/media_player_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../shared/providers/misskey_api_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../compose/emoji_picker_sheet.dart';
import '../ogp_provider.dart';
import '../timeline_provider.dart';

// ---- カスタム絵文字URLマップ（name → url） ----
final _emojiUrlMapProvider = Provider<Map<String, String>>((ref) {
  return ref
      .watch(customEmojisProvider)
      .when(
        data: (list) => {
          for (final e in list)
            if (e['name'] != null && e['url'] != null)
              e['name'] as String: e['url'] as String,
        },
        loading: () => {},
        error: (e, s) => {},
      );
});

// ---- NoteCard ----
class NoteCard extends ConsumerStatefulWidget {
  final NoteModel note;
  final bool navigatable;
  const NoteCard({super.key, required this.note, this.navigatable = true});

  @override
  ConsumerState<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<NoteCard> {
  late Map<String, int> _localReactions;
  String? _myReaction;

  @override
  void initState() {
    super.initState();
    _localReactions = Map.from(widget.note.reactions);
    _myReaction = widget.note.myReaction;
  }

  @override
  void didUpdateWidget(NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // タイムライン更新でnoteが差し替わった場合に同期
    if (oldWidget.note.id != widget.note.id) {
      _localReactions = Map.from(widget.note.reactions);
      _myReaction = widget.note.myReaction;
    }
  }

  // リアクション Chip またはピッカーからのリアクション操作を一元処理
  Future<void> _handleReaction(String reaction) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      if (_myReaction != null) {
        // すでにリアクション済み
        if (_myReaction == reaction) {
          // 同じリアクション → 削除
          await api.deleteReaction(widget.note.id);
          setState(() {
            _decrementReaction(_myReaction!);
            _myReaction = null;
          });
        } else {
          // 別のリアクション → 削除してから追加
          final old = _myReaction!;
          await api.deleteReaction(widget.note.id);
          setState(() {
            _decrementReaction(old);
            _myReaction = null;
          });
          await api.createReaction(widget.note.id, reaction);
          setState(() {
            _incrementReaction(reaction);
            _myReaction = reaction;
          });
        }
      } else {
        // 未リアクション → 追加
        await api.createReaction(widget.note.id, reaction);
        setState(() {
          _incrementReaction(reaction);
          _myReaction = reaction;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  void _incrementReaction(String key) {
    _localReactions[key] = (_localReactions[key] ?? 0) + 1;
  }

  void _decrementReaction(String key) {
    final current = _localReactions[key] ?? 0;
    if (current <= 1) {
      _localReactions.remove(key);
    } else {
      _localReactions[key] = current - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final theme = Theme.of(context);
    final emojiUrlMap = ref.watch(_emojiUrlMapProvider);

    // リノート（引用なし）の場合
    if (note.text == null && note.renote != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.repeat, size: 14, color: theme.colorScheme.tertiary),
                const SizedBox(width: 4),
                Text(
                  '${note.user.name} がリノート',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          NoteCard(note: note.renote!, navigatable: widget.navigatable),
        ],
      );
    }

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ユーザー情報
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push('/profile/${note.user.id}'),
                  child: note.user.avatarUrl != null
                      ? CircleAvatar(
                          radius: 20,
                          backgroundImage: CachedNetworkImageProvider(
                            note.user.avatarUrl!,
                          ),
                        )
                      : const CircleAvatar(
                          radius: 20,
                          child: Icon(Icons.person, size: 20),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.user.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        note.user.acct,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDateTime(
                    note.createdAt,
                    ref.watch(settingsProvider).dateTimeRelative,
                    ref.watch(settingsProvider).timezoneOffsetHours,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (note.visibility != AppConstants.visibilityPublic)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _visibilityIcon(note.visibility),
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),

            // 返信先
            if (note.reply != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Re: ${note.reply!.user.acct}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),

            // 本文（URLをタップ可能リンクとして表示）
            if (note.text != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _LinkedText(text: note.text!, emojiUrlMap: emojiUrlMap),
              ),

            // OGPカード（本文にURLが含まれる場合）
            if (note.text != null)
              Builder(
                builder: (_) {
                  final match = _LinkedText._urlRegex.firstMatch(note.text!);
                  if (match == null) return const SizedBox.shrink();
                  final url = match.group(0)!;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OgpCard(url: url),
                  );
                },
              ),

            // 添付メディア
            if (note.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _MediaGrid(files: note.files),
              ),

            // リアクション（ローカル状態から表示）
            if (_localReactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _localReactions.entries.map((e) {
                    final isSelected = _myReaction == e.key;
                    return _ReactionChip(
                      reactionKey: e.key,
                      count: e.value,
                      isSelected: isSelected,
                      emojiUrlMap: emojiUrlMap,
                      onTap: () => _handleReaction(e.key),
                    );
                  }).toList(),
                ),
              ),

            // アクションボタン
            _ActionBar(note: note, onReaction: _handleReaction),
          ],
        ),
      ),
    );

    if (!widget.navigatable) return card;
    return GestureDetector(
      onTap: () => context.push('/note/${note.id}', extra: note),
      child: card,
    );
  }

  String _formatDateTime(DateTime dt, bool relative, int? tzOffset) {
    if (relative) {
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
      if (diff.inHours < 24) return '${diff.inHours}時間前';
      return '${dt.toLocal().month}/${dt.toLocal().day}';
    } else {
      final d = tzOffset != null
          ? dt.toUtc().add(Duration(hours: tzOffset))
          : dt.toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    }
  }

  IconData _visibilityIcon(String visibility) {
    return switch (visibility) {
      AppConstants.visibilityHome => Icons.home_outlined,
      AppConstants.visibilityFollowers => Icons.lock_outline,
      AppConstants.visibilitySpecified => Icons.mail_outline,
      _ => Icons.public,
    };
  }
}

// ---- リアクション Chip（絵文字を画像表示） ----
class _ReactionChip extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool isSelected;
  final Map<String, String> emojiUrlMap;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.reactionKey,
    required this.count,
    required this.isSelected,
    required this.emojiUrlMap,
    required this.onTap,
  });

  /// `:honda@.:` → `honda`、`:wave:` → `wave`、それ以外は null（Unicode絵文字等）
  static String? _extractName(String key) {
    if (!key.startsWith(':') || !key.endsWith(':')) return null;
    final inner = key.substring(1, key.length - 1);
    final atIndex = inner.indexOf('@');
    return atIndex >= 0 ? inner.substring(0, atIndex) : inner;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _extractName(reactionKey);
    final imageUrl = name != null ? emojiUrlMap[name] : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                height: 18,
                width: 18,
                fit: BoxFit.contain,
                errorWidget: (context, url, error) =>
                    Text(reactionKey, style: const TextStyle(fontSize: 12)),
              )
            else
              Text(reactionKey, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- アクションバー ----
class _ActionBar extends ConsumerStatefulWidget {
  final NoteModel note;
  final Future<void> Function(String reaction) onReaction;

  const _ActionBar({required this.note, required this.onReaction});

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _isRenoting = false;

  Future<void> _showNoteMenu(BuildContext context) async {
    final activeAccount = ref.read(activeAccountProvider);
    final isOwn = activeAccount?.userId == widget.note.user.id;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // テキストコピー（全員）
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text(
                '\u30c6\u30ad\u30b9\u30c8\u3092\u30b3\u30d4\u30fc',
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final text = widget.note.text ?? '';
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '\u30c6\u30ad\u30b9\u30c8\u3092\u30b3\u30d4\u30fc\u3057\u307e\u3057\u305f',
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            // ブラウザで開く（全員）
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('ブラウザで開く'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final account = ref.read(activeAccountProvider);
                if (account == null) return;
                final uri = Uri.parse(
                  'https://${account.host}/notes/${widget.note.id}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            // 削除（自分の投稿のみ）
            if (isOwn) ...[
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '\u524a\u9664',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteNote(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('\u524a\u9664\u3057\u3066\u518d\u7de8\u96c6'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteAndEdit(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteNote(BuildContext context) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteNote(widget.note.id);
      // 全タイムラインから该当ノートを削除
      for (final type in [
        AppConstants.tabTypeHome,
        AppConstants.tabTypeLocal,
        AppConstants.tabTypeSocial,
        AppConstants.tabTypeGlobal,
      ]) {
        ref.read(timelineProvider(type).notifier).removeNote(widget.note.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u6295\u7a3f\u3092\u524a\u9664\u3057\u307e\u3057\u305f',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u524a\u9664\u306b\u5931\u6557\u3057\u307e\u3057\u305f: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteAndEdit(BuildContext context) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final note = widget.note;
    try {
      await api.deleteNote(note.id);
      for (final type in [
        AppConstants.tabTypeHome,
        AppConstants.tabTypeLocal,
        AppConstants.tabTypeSocial,
        AppConstants.tabTypeGlobal,
      ]) {
        ref.read(timelineProvider(type).notifier).removeNote(note.id);
      }
      if (context.mounted) {
        context.push(
          '/compose',
          extra: {
            'initialText': note.text ?? '',
            'visibility': note.visibility,
            'initialFiles': note.files,
            if (note.reply != null) 'replyId': note.reply!.id,
            if (note.reply != null) 'replyToNote': note.reply,
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u524a\u9664\u306b\u5931\u6557\u3057\u307e\u3057\u305f: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _renote() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isRenoting) return;
    setState(() => _isRenoting = true);
    try {
      await api.renote(widget.note.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('リノートしました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('リノートに失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRenoting = false);
    }
  }

  Future<void> _pickReaction() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const EmojiPickerSheet(),
    );
    if (name == null || !mounted) return;
    await widget.onReaction(':$name:');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeAccount = ref.read(activeAccountProvider);
    final canRenote =
        !(widget.note.visibility == AppConstants.visibilityFollowers &&
            widget.note.user.id != activeAccount?.userId);
    return Row(
      children: [
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          count: widget.note.repliesCount,
          onTap: () => context.push(
            '/compose',
            extra: {'replyId': widget.note.id, 'replyToNote': widget.note},
          ),
        ),
        _ActionButton(
          icon: _isRenoting ? Icons.hourglass_empty : Icons.repeat,
          count: widget.note.renoteCount,
          onTap: canRenote ? _renote : null,
          color: canRenote
              ? theme.colorScheme.tertiary
              : theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        _ActionButton(
          icon: Icons.add_reaction_outlined,
          count: 0,
          onTap: _pickReaction,
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: () => _showNoteMenu(context),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.count,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: c),
            if (count > 0) ...[
              const SizedBox(width: 2),
              Text('$count', style: TextStyle(fontSize: 12, color: c)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<DriveFileModel> files;

  const _MediaGrid({required this.files});

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 画像グリッド ──
        Builder(
          builder: (_) {
            final imageFiles = files.where((f) => f.isImage).toList();
            if (imageFiles.isEmpty) return const SizedBox.shrink();
            final count = imageFiles.length.clamp(1, 4);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count == 1 ? 1 : 2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: count == 1 ? 16 / 9 : 1,
              ),
              itemCount: count,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _FullscreenImageViewer(
                      urls: imageFiles.map((f) => f.url).toList(),
                      initialIndex: i,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imageFiles[i].thumbnailUrl ?? imageFiles[i].url,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          },
        ),

        // ── 動画 ──
        ...files
            .where((f) => f.isVideo)
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MediaPlayerScreen(url: f.url, title: f.name),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (f.thumbnailUrl != null)
                            CachedNetworkImage(
                              imageUrl: f.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  Container(color: Colors.black),
                            )
                          else
                            Container(color: Colors.black),
                          const Center(
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

        // ── 音声 ──
        ...files
            .where((f) => f.isAudio)
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _FileTile(
                  icon: Icons.audiotrack_outlined,
                  label: f.name,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MediaPlayerScreen(
                        url: f.url,
                        title: f.name,
                        isAudio: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),

        // ── その他 ──
        ...files
            .where((f) => !f.isImage && !f.isVideo && !f.isAudio)
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _FileTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: f.name,
                  onTap: () async {
                    final uri = Uri.tryParse(f.url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              ),
            ),
      ],
    );
  }
}

/// 音声・その他ファイルの行表示
class _FileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FileTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Icon(Icons.open_in_new, size: 14, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

// ---- フルサイズ画像ビューア ----
class _FullscreenImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _FullscreenImageViewer({
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.urls.length > 1
            ? Text(
                '${_current + 1} / ${widget.urls.length}',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: PageView.builder(
          controller: PageController(initialPage: widget.initialIndex),
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.urls[i],
                fit: BoxFit.contain,
                placeholder: (_, _) =>
                    const CircularProgressIndicator(color: Colors.white),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- URLをタップ可能リンクとして表示するウィジェット ----
class _LinkedText extends StatelessWidget {
  final String text;
  final Map<String, String> emojiUrlMap;

  // OgpCard から参照されるため public static で保持
  static final _urlRegex = RegExp(
    r'https?://[^\s\u3000\u300c\u300d\uff08\uff09\u300e\u300f]+',
    caseSensitive: false,
  );

  // URL と絵文字の両方を一括でマッチ（unicode モード）
  static final _tokenRegex = RegExp(
    // URLs
    r'(?:https?://[^\s\u3000\u300c\u300d\uff08\uff09\u300e\u300f]+)'
    // カスタム絵文字 :name: / :name@server:
    r'|(?::[a-zA-Z0-9_]+(?:@[a-zA-Z0-9._-]*)?:)'
    // 国旗 (regional indicator ペア)
    r'|(?:[\u{1F1E6}-\u{1F1FF}]{2})'
    // SMP 絵文字 (肌色修飾子 + ZWJシーケンス含む)
    r'|(?:[\u{1F004}-\u{1FAFF}](?:\u{FE0F})?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}(?:[\u{1F004}-\u{1FAFF}]|[\u2640\u2642\u2695\u2696\u2708\u2764])(?:\u{FE0F})?(?:[\u{1F3FB}-\u{1F3FF}])?)*)'
    // BMP 記号絵文字 (☀️ 等) + 任意 VS16
    r'|(?:[\u2194-\u27BF]\u{FE0F}?)',
    unicode: true,
    caseSensitive: false,
  );

  static const _maxUrlDisplayLength = 40;

  static String _twemojiUrl(String emoji) {
    final parts = emoji.runes.map((r) => r.toRadixString(16)).join('-');
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$parts.png';
  }

  const _LinkedText({required this.text, required this.emojiUrlMap});

  static String _emojiName(String token) {
    final inner = token.substring(1, token.length - 1);
    final atIdx = inner.indexOf('@');
    return atIdx >= 0 ? inner.substring(0, atIdx) : inner;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _tokenRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith(':')) {
        // カスタム絵文字
        final name = _emojiName(token);
        final url = emojiUrlMap[name];
        if (url != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CachedNetworkImage(
                imageUrl: url,
                height: 20,
                width: 20,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => Text(token),
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: token));
        }
      } else if (token.startsWith('http')) {
        // URL → 長い場合は短縮表示
        final display = token.length > _maxUrlDisplayLength
            ? '${token.substring(0, _maxUrlDisplayLength - 1)}\u2026'
            : token;
        spans.add(
          TextSpan(
            text: display,
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                final uri = Uri.tryParse(token);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
          ),
        );
      } else {
        // Unicode 絵文字 → Twemoji CDN で描画
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CachedNetworkImage(
              imageUrl: _twemojiUrl(token),
              height: 20,
              width: 20,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  Text(token, style: theme.textTheme.bodyMedium),
            ),
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: theme.textTheme.bodyMedium, children: spans),
    );
  }
}
