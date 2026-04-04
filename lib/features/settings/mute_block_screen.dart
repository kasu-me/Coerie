import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/misskey_api_provider.dart';

// ---- エラーメッセージ変換 ----
String _apiErrorMessage(Object e) {
  if (e is DioException) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 403) return '権限がありません。このAPIには追加の権限スコープが必要です。';
    if (statusCode == 401) return '認証エラーです。再ログインしてください。';
    if (statusCode == 404) return 'このサーバーでは対応していません。';
    if (statusCode != null) return 'サーバーエラー ($statusCode)';
    return 'ネットワークエラー: ${e.message}';
  }
  return e.toString();
}

// ---- プロバイダー ----

final _mutingListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final api = ref.watch(misskeyApiProvider);
      if (api == null) return [];
      return api.getMutingList();
    });

final _blockingListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final api = ref.watch(misskeyApiProvider);
      if (api == null) return [];
      return api.getBlockingList();
    });

final _mutedWordsProvider = FutureProvider<List<List<String>>>((ref) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getMutedWords();
});

// ---- 画面 ----

class MuteBlockScreen extends ConsumerStatefulWidget {
  const MuteBlockScreen({super.key});

  @override
  ConsumerState<MuteBlockScreen> createState() => _MuteBlockScreenState();
}

class _MuteBlockScreenState extends ConsumerState<MuteBlockScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ミュート・ブロック'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ワードミュート'),
            Tab(text: 'ユーザーミュート'),
            Tab(text: 'ブロック'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_WordMuteTab(), _UserMuteTab(), _UserBlockTab()],
      ),
    );
  }
}

// ---- ワードミュートタブ ----

class _WordMuteTab extends ConsumerStatefulWidget {
  const _WordMuteTab();

  @override
  ConsumerState<_WordMuteTab> createState() => _WordMuteTabState();
}

class _WordMuteTabState extends ConsumerState<_WordMuteTab> {
  Future<void> _addWord(List<List<String>> current) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ワードミュートを追加'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ミュートしたいキーワード',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final updated = [
      ...current,
      [result],
    ];
    try {
      await api.setMutedWords(updated);
      ref.invalidate(_mutedWordsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
      }
    }
  }

  Future<void> _removeWord(List<List<String>> current, int index) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final updated = List<List<String>>.from(current)..removeAt(index);
    try {
      await api.setMutedWords(updated);
      ref.invalidate(_mutedWordsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutedAsync = ref.watch(_mutedWordsProvider);

    return mutedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: _apiErrorMessage(e),
        onRetry: () => ref.invalidate(_mutedWordsProvider),
      ),
      data: (words) => Scaffold(
        body: words.isEmpty
            ? const Center(child: Text('ワードミュートはありません'))
            : ListView.builder(
                itemCount: words.length,
                itemBuilder: (_, i) {
                  final label = words[i].join(' ');
                  return ListTile(
                    title: Text(label),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _removeWord(words, i),
                    ),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _addWord(words),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

// ---- ユーザーミュートタブ ----

class _UserMuteTab extends ConsumerWidget {
  const _UserMuteTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_mutingListProvider);

    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: _apiErrorMessage(e),
        onRetry: () => ref.invalidate(_mutingListProvider),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_mutingListProvider);
          await ref
              .read(_mutingListProvider.future)
              .catchError((_) => <Map<String, dynamic>>[]);
        },
        child: list.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('ミュートしているユーザーはいません')),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final mutee = list[i]['mutee'] as Map<String, dynamic>?;
                  if (mutee == null) return const SizedBox.shrink();
                  final name =
                      mutee['name'] as String? ??
                      mutee['username'] as String? ??
                      '';
                  final username = mutee['username'] as String? ?? '';
                  final host = mutee['host'] as String? ?? '';
                  final acct = host.isEmpty ? '@$username' : '@$username@$host';
                  final avatarUrl = mutee['avatarUrl'] as String?;
                  final userId = mutee['id'] as String? ?? '';

                  return ListTile(
                    leading: avatarUrl != null
                        ? CircleAvatar(
                            backgroundImage: CachedNetworkImageProvider(
                              avatarUrl,
                            ),
                          )
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(acct),
                    onTap: () => context.push('/profile/$userId'),
                    trailing: TextButton(
                      onPressed: () => _unmute(context, ref, userId),
                      child: const Text('解除'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _unmute(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.unmuteUser(userId);
      ref.invalidate(_mutingListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ミュート解除に失敗しました: $e')));
      }
    }
  }
}

// ---- ユーザーブロックタブ ----

class _UserBlockTab extends ConsumerWidget {
  const _UserBlockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_blockingListProvider);

    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: _apiErrorMessage(e),
        onRetry: () => ref.invalidate(_blockingListProvider),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_blockingListProvider);
          await ref
              .read(_blockingListProvider.future)
              .catchError((_) => <Map<String, dynamic>>[]);
        },
        child: list.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('ブロックしているユーザーはいません')),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final blockee = list[i]['blockee'] as Map<String, dynamic>?;
                  if (blockee == null) return const SizedBox.shrink();
                  final name =
                      blockee['name'] as String? ??
                      blockee['username'] as String? ??
                      '';
                  final username = blockee['username'] as String? ?? '';
                  final host = blockee['host'] as String? ?? '';
                  final acct = host.isEmpty ? '@$username' : '@$username@$host';
                  final avatarUrl = blockee['avatarUrl'] as String?;
                  final userId = blockee['id'] as String? ?? '';

                  return ListTile(
                    leading: avatarUrl != null
                        ? CircleAvatar(
                            backgroundImage: CachedNetworkImageProvider(
                              avatarUrl,
                            ),
                          )
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(acct),
                    onTap: () => context.push('/profile/$userId'),
                    trailing: TextButton(
                      onPressed: () => _unblock(context, ref, userId),
                      child: const Text('解除'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.unblockUser(userId);
      ref.invalidate(_blockingListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ブロック解除に失敗しました: $e')));
      }
    }
  }
}
// ---- エラー表示ウィジェット ----

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}
