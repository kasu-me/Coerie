import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import 'widgets/note_card.dart';

// 先祖ノートチェーン（古い順）を再帰的に取得する
final _ancestorsProvider = FutureProvider.family<List<NoteModel>, NoteModel>((
  ref,
  note,
) async {
  final api = ref.read(misskeyApiProvider);
  if (api == null) return [];

  final ancestors = <NoteModel>[];
  NoteModel? current = note;

  while (true) {
    // reply フィールドがある場合はそこから replyId を取得
    final replyId = current?.reply?.id;
    if (replyId == null) break;

    try {
      final parent = await api.getNote(replyId);
      ancestors.insert(0, parent);
      current = parent;
    } catch (_) {
      break;
    }
  }

  return ancestors;
});

final _noteRepliesProvider = FutureProvider.family<List<NoteModel>, String>((
  ref,
  noteId,
) async {
  final api = ref.read(misskeyApiProvider);
  if (api == null) return [];
  return api.getNoteReplies(noteId);
});

class NoteDetailScreen extends ConsumerWidget {
  final NoteModel note;
  const NoteDetailScreen({super.key, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancestorsAsync = ref.watch(_ancestorsProvider(note));
    final repliesAsync = ref.watch(_noteRepliesProvider(note.id));

    return Scaffold(
      appBar: AppBar(title: const Text('スレッド')),
      body: ListView(
        children: [
          // 先祖ノートを古い順に表示
          ...ancestorsAsync.maybeWhen(
            data: (ancestors) => ancestors
                .expand<Widget>(
                  (n) => [
                    NoteCard(note: n, navigatable: false),
                    const Divider(height: 1),
                  ],
                )
                .toList(),
            loading: () => [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            orElse: () => [],
          ),
          NoteCard(note: note, navigatable: false),
          const Divider(height: 1),
          repliesAsync.when(
            data: (replies) {
              if (replies.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('返信はありません')),
                );
              }
              return Column(
                children: replies
                    .map((r) => NoteCard(note: r, navigatable: false))
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('返信の読み込みに失敗しました: $e'),
            ),
          ),
        ],
      ),
    );
  }
}
