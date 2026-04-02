import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
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

class NoteDetailScreen extends ConsumerStatefulWidget {
  final NoteModel note;
  const NoteDetailScreen({super.key, required this.note});

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final ancestorsAsync = ref.watch(_ancestorsProvider(note));
    final repliesAsync = ref.watch(_noteRepliesProvider(note.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('スレッド')),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ScrollToTopFab(scrollController: _scrollController),
      body: ListView(
        controller: _scrollController,
        children: [
          // ── 先祖ノート（上）: opacity を落とし文脈であることを示す ──
          ...ancestorsAsync.maybeWhen(
            data: (ancestors) => ancestors
                .map<Widget>(
                  (n) => Opacity(
                    opacity: 0.55,
                    child: NoteCard(note: n, navigatable: true),
                  ),
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

          // ── フォーカスノート: primary 色の左ボーダーと淡い背景で強調 ──
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            child: NoteCard(note: note, navigatable: false),
          ),

          // ── 返信（下）: インデントしてスレッド感を演出 ──
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
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: NoteCard(note: r, navigatable: true),
                      ),
                    )
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
