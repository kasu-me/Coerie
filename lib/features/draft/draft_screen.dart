import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/draft_model.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'draft_provider.dart';
import 'widgets/draft_attachment_thumbnail.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/utils/visibility_utils.dart';

/// 保存時の並び順（[DraftLocalFileModel.position]）のまま1本のリストに復元する。
///
/// 並びが compose 側とずれると一覧とエディタで見え方が食い違うため、
/// compose_screen.dart の _restoreAttachedMedia と同じ手順で組み立てる。
List<DraftAttachment> _mergedAttachments(DraftModel draft) {
  final result = draft.files
      .map<DraftAttachment>(DriveDraftAttachment.new)
      .toList();
  final locals = draft.localFiles.toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final local in locals) {
    if (local.position < 0 || local.position > result.length) {
      result.add(LocalDraftAttachment(local));
    } else {
      result.insert(local.position, LocalDraftAttachment(local));
    }
  }
  return result;
}

/// 「何に対する下書きか」を示す行。
///
/// 返信と引用は同時に成立しうるため、両方あるときは並べて出す。表示する
/// acct は下書き保存時に写したもので、相手が改名しても追従しない（一覧で
/// ノートを引き直すと下書きの件数だけ通信が発生するため）。
class _DraftRelationLine extends StatelessWidget {
  final DraftModel draft;
  const _DraftRelationLine(this.draft);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
    );
    final children = <Widget>[];
    void add(IconData icon, String label) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(Icon(icon, size: 12, color: theme.colorScheme.primary));
      children.add(const SizedBox(width: 4));
      children.add(
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      );
    }

    if (draft.replyId != null) add(Icons.reply, draft.replyAcct ?? '返信');
    if (draft.renoteId != null) {
      add(Icons.format_quote, draft.renoteAcct ?? '引用');
    }
    return Row(children: children);
  }
}

class DraftScreen extends ConsumerWidget {
  const DraftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('下書き')),
      body: drafts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  const Text('保存された下書きはありません'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                final attachments = _mergedAttachments(draft);
                final hasRelation =
                    draft.replyId != null || draft.renoteId != null;
                return Dismissible(
                  key: Key(draft.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) => confirmAction(
                    context,
                    ref,
                    title: '下書きを削除',
                    message: 'この下書きを削除しますか？',
                    confirmLabel: '削除',
                  ),
                  onDismissed: (_) =>
                      ref.read(draftProvider.notifier).deleteDraft(draft.id),
                  child: ListTile(
                    leading: attachments.isEmpty
                        ? null
                        : DraftLeadingThumbnail(attachments),
                    title: draft.text.trim().isEmpty
                        ? Text(
                            '（本文なし）',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          )
                        : Text(
                            draft.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    isThreeLine: hasRelation,
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasRelation) _DraftRelationLine(draft),
                        Row(
                          children: [
                            Icon(
                              visibilityIcon(draft.visibility),
                              size: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppConstants.visibilityLabels[draft.visibility] ??
                                  '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatYmdHm(draft.savedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () {
                      context.pop();
                      context.push('/compose?draftId=${draft.id}');
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          ref,
                          title: '下書きを削除',
                          message: 'この下書きを削除しますか？',
                          confirmLabel: '削除',
                        );
                        if (confirmed) {
                          ref
                              .read(draftProvider.notifier)
                              .deleteDraft(draft.id);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
