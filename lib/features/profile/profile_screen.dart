import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/user_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';

// ユーザー情報プロバイダー
final userProfileProvider = FutureProvider.family<UserModel, String>((
  ref,
  userId,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) throw Exception('未ログイン');
  return api.getUser(userId);
});

// ユーザー投稿プロバイダー
final userNotesProvider = FutureProvider.family<List<NoteModel>, String>((
  ref,
  userId,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) throw Exception('未ログイン');
  return api.getUserNotes(userId: userId, limit: 20);
});

class ProfileScreen extends ConsumerWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(e.toString().replaceFirst('Exception: ', '')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(userProfileProvider(userId)),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
        data: (user) => _ProfileBody(user: user, userId: userId),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final UserModel user;
  final String userId;

  const _ProfileBody({required this.user, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(userNotesProvider(userId));

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                // バナー画像
                if (user.bannerUrl != null)
                  CachedNetworkImage(
                    imageUrl: user.bannerUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, error, stack) =>
                        Container(color: theme.colorScheme.primaryContainer),
                  )
                else
                  Container(color: theme.colorScheme.primaryContainer),
                // グラデーション
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black45],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // アバター
                    CircleAvatar(
                      radius: 36,
                      backgroundImage: user.avatarUrl != null
                          ? CachedNetworkImageProvider(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? const Icon(Icons.person, size: 36)
                          : null,
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                // 表示名
                Text(
                  user.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                // @username
                Text(
                  '@${user.username}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                // 自己紹介
                if (user.description != null) ...[
                  const SizedBox(height: 8),
                  Text(user.description!),
                ],
                // フォロー/フォロワー数
                if (user.followingCount != null ||
                    user.followersCount != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (user.followingCount != null) ...[
                        _CountChip(count: user.followingCount!, label: 'フォロー'),
                        const SizedBox(width: 16),
                      ],
                      if (user.followersCount != null)
                        _CountChip(count: user.followersCount!, label: 'フォロワー'),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '投稿',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(e.toString().replaceFirst('Exception: ', ''))),
        data: (notes) => notes.isEmpty
            ? const Center(child: Text('投稿がありません'))
            : ListView.builder(
                itemCount: notes.length,
                itemBuilder: (context, i) => NoteCard(note: notes[i]),
              ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;

  const _CountChip({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
