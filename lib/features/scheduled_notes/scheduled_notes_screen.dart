import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/note_draft_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/utils/visibility_utils.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/error_view.dart';
import '../draft/widgets/draft_attachment_thumbnail.dart';
import 'scheduled_notes_provider.dart';

/// アクティブアカウントの予約投稿一覧。
///
/// 予約日時は端末のローカル時刻で表示する。設定の「タイムゾーン」に合わせないのは、
/// 予約時の日時ピッカーが端末のローカル時刻で入力させるため。
class ScheduledNotesScreen extends ConsumerWidget {
  const ScheduledNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(scheduledNotesProvider);
    final accountId = ref.watch(activeAccountProvider.select((a) => a?.id));
    final limit = accountId == null
        ? null
        : ref.watch(scheduledNoteLimitProvider(accountId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('予約投稿')),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: apiErrorMessage(e, fallback: '予約投稿を取得できませんでした'),
          onRetry: () => ref.invalidate(scheduledNotesProvider),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(scheduledNotesProvider.future),
          child: items.isEmpty
              ? _EmptyView(limit: limit)
              : ListView.separated(
                  // RefreshIndicator を件数が少なくても引けるようにする。
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length + 1,
                  separatorBuilder: (_, i) => i == 0
                      ? const SizedBox.shrink()
                      : const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _CountHeader(count: items.length, limit: limit);
                    }
                    return _ScheduledNoteTile(note: items[index - 1]);
                  },
                ),
        ),
      ),
    );
  }
}

/// 「予約中 n / 上限 件」。既定の上限は1件と少なく、追加で予約できない理由に
/// 気付けるよう一覧の先頭に出す。
class _CountHeader extends StatelessWidget {
  final int count;
  final int? limit;
  const _CountHeader({required this.count, required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = limit != null && limit! > 0
        ? '予約中 $count / $limit 件'
        : '予約中 $count 件';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final int? limit;
  const _EmptyView({required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // RefreshIndicator で引けるよう、空表示もスクロール可能にしておく。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_send,
                  size: 64,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                const Text('予約投稿はありません'),
                const SizedBox(height: 8),
                Text(
                  '投稿画面の予約ボタンから日時を指定して予約できます',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (limit != null && limit! > 0)
                  Text(
                    '（最大$limit件）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduledNoteTile extends ConsumerWidget {
  final NoteDraftModel note;
  const _ScheduledNoteTile({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final failed = note.isPostFailed;
    final attachments = note.files
        .map<DraftAttachment>(DriveDraftAttachment.new)
        .toList();
    final text = note.text?.trim() ?? '';

    return ListTile(
      leading: attachments.isEmpty ? null : DraftLeadingThumbnail(attachments),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScheduleLine(note: note, failed: failed),
          const SizedBox(height: 4),
          if (note.cw != null && note.cw!.isNotEmpty)
            Text(
              'CW: ${note.cw}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          text.isEmpty
              ? Text(
                  note.poll != null ? '（投票）' : '（本文なし）',
                  style: TextStyle(color: theme.colorScheme.outline),
                )
              : Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RelationLine(note: note),
            Row(
              children: [
                Icon(
                  visibilityIcon(note.visibility),
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  AppConstants.visibilityLabels[note.visibility] ?? '',
                  style: theme.textTheme.bodySmall,
                ),
                if (note.poll != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.poll, size: 12, color: theme.colorScheme.outline),
                  const SizedBox(width: 2),
                  Text('投票', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '予約日時に投稿できませんでした。タップして日時を指定し直すと再度予約できます',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      onTap: () => _edit(context, ref),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '予約を取り消し',
        onPressed: () => _delete(context, ref),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await context.push<bool>('/compose', extra: {'scheduledDraft': note});
    // 編集画面での更新・今すぐ投稿のほか、編集中にサーバーが投稿を
    // 済ませていることもあるため、結果によらず取り直す。
    ref.invalidate(scheduledNotesProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      ref,
      title: '予約を取り消し',
      message: 'この予約投稿を取り消しますか？\n取り消した内容は元に戻せません。',
      confirmLabel: '取り消し',
    );
    if (!confirmed) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteNoteDraft(note.id);
    } catch (e) {
      // 既に投稿・削除済みなら一覧から消えれば目的は果たせているので伏せる。
      if (apiErrorCode(e) != 'NO_SUCH_NOTE_DRAFT' && context.mounted) {
        showApiErrorSnackBar(context, e, fallback: '予約の取り消しに失敗しました');
      }
    }
    ref.invalidate(scheduledNotesProvider);
  }
}

/// 予約日時の行。投稿に失敗したものはエラー色にして目立たせる。
class _ScheduleLine extends StatelessWidget {
  final NoteDraftModel note;
  final bool failed;
  const _ScheduleLine({required this.note, required this.failed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = failed ? theme.colorScheme.error : theme.colorScheme.primary;
    final at = note.scheduledAt;
    return Row(
      children: [
        Icon(
          failed ? Icons.error_outline : Icons.schedule,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            at == null ? '日時未設定' : formatYmdWeekdayHm(at),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (failed) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '投稿失敗',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 返信先・引用元・チャンネルを示す行。どれも無ければ何も出さない。
class _RelationLine extends StatelessWidget {
  final NoteDraftModel note;
  const _RelationLine({required this.note});

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

    if (note.replyId != null) add(Icons.reply, note.reply?.user.acct ?? '返信');
    if (note.renoteId != null) {
      add(Icons.format_quote, note.renote?.user.acct ?? '引用');
    }
    if (note.channelId != null) add(Icons.tag, note.channelName ?? 'チャンネル');
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: children),
    );
  }
}
