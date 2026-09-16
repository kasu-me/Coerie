import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/muted_word_model.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/word_mute_provider.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/user_avatar.dart';

// ---- プロバイダー ----

final _mutingListProvider = FutureProvider.autoDispose<List<UserModel>>((
  ref,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getMutingList();
});

final _blockingListProvider = FutureProvider.autoDispose<List<UserModel>>((
  ref,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getBlockingList();
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
    _tabController = TabController(length: 4, vsync: this);
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
          // 4つ並ぶとタブ名が省略されて区別しにくくなるため横スクロールにする。
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'ワードミュート'),
            Tab(text: 'ハードワードミュート'),
            Tab(text: 'ユーザーミュート'),
            Tab(text: 'ブロック'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WordMuteTab(),
          _WordMuteTab(hard: true),
          _UserMuteTab(),
          _UserBlockTab(),
        ],
      ),
    );
  }
}

// ---- ワードミュートタブ ----

/// ワードミュートの一覧タブ。
///
/// [hard] が true のときはハードワードミュート（hardMutedWords）を編集する。
class _WordMuteTab extends ConsumerStatefulWidget {
  final bool hard;

  const _WordMuteTab({this.hard = false});

  @override
  ConsumerState<_WordMuteTab> createState() => _WordMuteTabState();
}

class _WordMuteTabState extends ConsumerState<_WordMuteTab> {
  bool get _hard => widget.hard;

  /// ワードを1件追加する。
  ///
  /// i/update は差分更新ではなく全置換のため、変更後の全エントリを送る。
  Future<void> _addWord(List<MutedWordModel> current) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_hard ? 'ハードワードミュートを追加' : 'ワードミュートを追加'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ミュートしたいキーワード（/正規表現/i も可）',
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
    // `/pattern/flags` 形式は本家と同じく正規表現として登録する。
    final word = MutedWordModel.fromJson(result);
    if (word == null) return;
    await _save([...current, word], fallback: '追加に失敗しました');
  }

  Future<void> _removeWord(List<MutedWordModel> current, int index) async {
    final confirmed = await confirmAction(
      context,
      ref,
      title: _hard ? 'ハードワードミュートを削除' : 'ワードミュートを削除',
      message: '「${current[index].label}」を削除しますか？この操作は取り消せません。',
      confirmLabel: '削除',
    );
    if (!confirmed) return;
    final updated = List<MutedWordModel>.from(current)..removeAt(index);
    await _save(updated, fallback: '削除に失敗しました');
  }

  Future<void> _save(
    List<MutedWordModel> words, {
    required String fallback,
  }) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      if (_hard) {
        await api.setHardMutedWords(words);
      } else {
        await api.setMutedWords(words);
      }
      ref.invalidate(mutedWordsProvider);
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: fallback);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutedAsync = ref.watch(mutedWordsProvider);

    return mutedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: apiErrorMessage(e, fallback: 'ワードミュートを取得できませんでした'),
        onRetry: () => ref.invalidate(mutedWordsProvider),
      ),
      data: (settings) {
        final words = _hard ? settings.hard : settings.soft;
        return Scaffold(
          body: words.isEmpty
              ? Center(
                  child: Text(_hard ? 'ハードワードミュートはありません' : 'ワードミュートはありません'),
                )
              : ListView.builder(
                  // FAB に隠れる最後の1件を操作できるよう下に余白を取る。
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: words.length,
                  itemBuilder: (_, i) {
                    final word = words[i];
                    return ListTile(
                      title: Text(word.label),
                      subtitle: word.isRegex ? const Text('正規表現') : null,
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        tooltip: '削除',
                        onPressed: () => _removeWord(words, i),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _addWord(words),
            tooltip: 'ワードを追加',
            child: const Icon(Icons.add),
          ),
        );
      },
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
      error: (e, _) => ErrorView(
        message: apiErrorMessage(e, fallback: 'ミュート中のユーザーを取得できませんでした'),
        onRetry: () => ref.invalidate(_mutingListProvider),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_mutingListProvider);
          await ref
              .read(_mutingListProvider.future)
              .catchError((_) => <UserModel>[]);
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
                  final mutee = list[i];

                  return ListTile(
                    leading: UserAvatar(avatarUrl: mutee.avatarUrl),
                    title: Text(mutee.name),
                    subtitle: Text(mutee.acct),
                    onTap: () => context.push('/profile/${mutee.id}'),
                    trailing: TextButton(
                      onPressed: () => _unmute(context, ref, mutee.id),
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
        showApiErrorSnackBar(context, e, fallback: 'ミュート解除に失敗しました');
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
      error: (e, _) => ErrorView(
        message: apiErrorMessage(e, fallback: 'ブロック中のユーザーを取得できませんでした'),
        onRetry: () => ref.invalidate(_blockingListProvider),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_blockingListProvider);
          await ref
              .read(_blockingListProvider.future)
              .catchError((_) => <UserModel>[]);
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
                  final blockee = list[i];

                  return ListTile(
                    leading: UserAvatar(avatarUrl: blockee.avatarUrl),
                    title: Text(blockee.name),
                    subtitle: Text(blockee.acct),
                    onTap: () => context.push('/profile/${blockee.id}'),
                    trailing: TextButton(
                      onPressed: () => _unblock(context, ref, blockee.id),
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
        showApiErrorSnackBar(context, e, fallback: 'ブロック解除に失敗しました');
      }
    }
  }
}

// ---- エラー表示ウィジェット ----
