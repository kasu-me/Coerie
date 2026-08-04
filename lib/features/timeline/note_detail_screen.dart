import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
import 'widgets/note_card.dart';

/// 指定した返信先IDから親を辿り、先祖ノートチェーン（古い順）を取得する。
///
/// family のキーは必ず ID（値の等価性が成立するもの）にすること。
/// NoteModel は == を実装していないため、キーにするとインスタンスが変わるたび
/// 別プロバイダーとして生成され、再取得と無制限のキャッシュ蓄積を招く。
final _ancestorsProvider = FutureProvider.autoDispose
    .family<List<NoteModel>, String>((ref, replyId) async {
      final api = ref.read(misskeyApiProvider);
      if (api == null) return [];

      final ancestors = <NoteModel>[];
      String? currentReplyId = replyId;

      while (currentReplyId != null) {
        try {
          final parent = await api.getNote(currentReplyId);
          ancestors.insert(0, parent);
          currentReplyId = parent.reply?.id;
        } catch (_) {
          break;
        }
      }

      return ancestors;
    });

final _noteRepliesProvider = FutureProvider.autoDispose
    .family<List<NoteModel>, String>((ref, noteId) async {
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
    // 返信でないノートは先祖を辿る必要がないため、プロバイダーを生成しない
    final rootReplyId = note.reply?.id;
    final ancestorsAsync = rootReplyId == null
        ? const AsyncValue<List<NoteModel>>.data([])
        : ref.watch(_ancestorsProvider(rootReplyId));
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
              child: Text(apiErrorMessage(e, fallback: '返信を読み込めませんでした')),
            ),
          ),
        ],
      ),
    );
  }
}
