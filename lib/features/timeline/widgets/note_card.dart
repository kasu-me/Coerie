import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/note_model.dart';
import '../../../core/constants/app_constants.dart';

class NoteCard extends StatelessWidget {
  final NoteModel note;

  const NoteCard({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // リノートの場合
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
          NoteCard(note: note.renote!),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                GestureDetector(
                  onTap: () {
                    // TODO: 投稿詳細画面へ遷移
                  },
                  child: Text(
                    _formatDateTime(note.createdAt),
                    style: theme.textTheme.bodySmall,
                  ),
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

            // 本文
            if (note.text != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(note.text!),
              ),

            // 添付メディア
            if (note.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _MediaGrid(files: note.files),
              ),

            // リアクション
            if (note.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: note.reactions.entries.map((e) {
                    return Chip(
                      label: Text(
                        '${e.key} ${e.value}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ),

            // アクションボタン
            const SizedBox(height: 4),
            _ActionBar(note: note),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${dt.month}/${dt.day}';
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

class _MediaGrid extends StatelessWidget {
  final List<DriveFileModel> files;

  const _MediaGrid({required this.files});

  @override
  Widget build(BuildContext context) {
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
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: imageFiles[i].thumbnailUrl ?? imageFiles[i].url,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final NoteModel note;

  const _ActionBar({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          count: note.repliesCount,
          onTap: () {}, // TODO: 返信
        ),
        const SizedBox(width: 16),
        _ActionButton(
          icon: Icons.repeat,
          count: note.renoteCount,
          onTap: () {}, // TODO: リノート
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(width: 16),
        _ActionButton(
          icon: Icons.add_reaction_outlined,
          count: 0,
          onTap: () {}, // TODO: リアクション
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: () {}, // TODO: その他メニュー
          style: IconButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.outline;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          if (count > 0) ...[
            const SizedBox(width: 2),
            Text('$count', style: TextStyle(fontSize: 12, color: c)),
          ],
        ],
      ),
    );
  }
}
