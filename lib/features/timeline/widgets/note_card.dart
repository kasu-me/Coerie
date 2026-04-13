import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/models/clip_model.dart';
import '../../../data/models/note_model.dart';
import '../../../data/models/poll_model.dart';
import '../../../data/models/user_model.dart';
import '../../../shared/widgets/media_player_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../shared/providers/misskey_api_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import 'package:coerie/features/profile/pinned_notes_provider.dart';
import '../../../core/streaming/streaming_service.dart';
import '../../../shared/widgets/mfm_content.dart';
import '../../../shared/widgets/report_abuse_sheet.dart';
import '../../../core/router/app_router.dart';
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
  final UserModel? renoteUser;
  final bool isMyRenote;
  final String? renoteWrapperNoteId;
  final UserModel? pinnedByUser;
  final VoidCallback? onPinnedChanged;
  const NoteCard({
    super.key,
    required this.note,
    this.navigatable = true,
    this.renoteUser,
    this.isMyRenote = false,
    this.renoteWrapperNoteId,
    this.pinnedByUser,
    this.onPinnedChanged,
  });

  @override
  ConsumerState<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<NoteCard> {
  late Map<String, int> _localReactions;
  String? _myReaction;
  bool _cwExpanded = false;
  final Set<int> _revealedSensitiveIndexes = {};
  StreamSubscription<NoteUpdateEvent>? _noteUpdateSub;
  PollModel? _localPoll;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _localReactions = Map.from(widget.note.reactions);
    _myReaction = widget.note.myReaction;
    _localPoll = widget.note.poll;
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeNote());
  }

  void _subscribeNote() {
    final streaming = ref.read(streamingServiceProvider);
    if (streaming == null) return;
    final noteId = widget.note.id;
    streaming.subNote(noteId);
    _noteUpdateSub = streaming.noteUpdateStream
        .where((e) => e.noteId == noteId)
        .listen(_onNoteUpdate);
  }

  void _onNoteUpdate(NoteUpdateEvent event) {
    if (!mounted) return;
    final activeUserId = ref.read(activeAccountProvider)?.userId;
    // 自分の操作は _handleReaction で既に反映済みなのでスキップ
    if (event.userId == activeUserId) return;
    // 投票イベントはここでは処理しない（ローカル更新は投票操作時に行う）
    if (event.type == 'pollVoted') return;

    setState(() {
      if (event.type == 'reacted' && event.reaction != null) {
        _incrementReaction(event.reaction!);
      } else if (event.type == 'unreacted' && event.reaction != null) {
        _decrementReaction(event.reaction!);
      }
    });
  }

  Future<void> _onMentionTap(String username, String? host) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final user = await api.getUserByUsername(username, userHost: host);
      if (mounted) context.push('/profile/${user.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ユーザーが見つかりませんでした: @$username')));
      }
    }
  }

  Future<void> _handleVote(int idx) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _localPoll == null || _isVoting) return;
    final choice = _localPoll!.choices[idx];
    if (choice.isVoted) return;
    if (!_localPoll!.multiple && _localPoll!.choices.any((c) => c.isVoted)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('既に投票済みです')));
      return;
    }

    setState(() => _isVoting = true);
    try {
      await api.votePoll(widget.note.id, idx);
      // optimistic update
      final updated = _localPoll!.choices.map((c) => c).toList();
      final prev = updated[idx];
      updated[idx] = PollChoiceModel(
        text: prev.text,
        votes: prev.votes + 1,
        isVoted: true,
      );
      _localPoll = PollModel(
        multiple: _localPoll!.multiple,
        expiresAt: _localPoll!.expiresAt,
        choices: updated,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('投票に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isVoting = false);
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

  @override
  void didUpdateWidget(NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // タイムライン更新でnoteが差し替わった場合に同期
    if (oldWidget.note.id != widget.note.id) {
      _localReactions = Map.from(widget.note.reactions);
      _myReaction = widget.note.myReaction;
      _cwExpanded = false;
      _revealedSensitiveIndexes.clear();
      _localPoll = widget.note.poll;
      // 購読し直し
      final streaming = ref.read(streamingServiceProvider);
      if (streaming != null) {
        _noteUpdateSub?.cancel();
        streaming.unsubNote(oldWidget.note.id);
        streaming.subNote(widget.note.id);
        _noteUpdateSub = streaming.noteUpdateStream
            .where((e) => e.noteId == widget.note.id)
            .listen(_onNoteUpdate);
      }
    }
  }

  Future<void> _showReactionUsers(String reactionKey) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (ctx) {
                          final localEmojiMap = ref.read(_emojiUrlMapProvider);
                          final emojiUrlMap = {
                            ...localEmojiMap,
                            ...widget.note.emojis,
                            ...widget.note.reactionEmojis,
                          };

                          final inner = _ReactionChip._inner(reactionKey);
                          String? imageUrl;
                          if (inner != null) {
                            imageUrl = emojiUrlMap[inner];
                            if (imageUrl == null) {
                              final atIdx = inner.indexOf('@');
                              final nameOnly = atIdx >= 0
                                  ? inner.substring(0, atIdx)
                                  : inner;
                              imageUrl = emojiUrlMap[nameOnly];
                            }
                          }

                          Widget iconWidget;
                          if (imageUrl != null) {
                            iconWidget = CachedNetworkImage(
                              imageUrl: imageUrl,
                              height: 22,
                              width: 22,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Text(
                                reactionKey,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            );
                          } else {
                            final twUrl = _ReactionChip._twemojiUrl(
                              reactionKey,
                            );
                            iconWidget = CachedNetworkImage(
                              imageUrl: twUrl,
                              height: 22,
                              width: 22,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Text(
                                reactionKey,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            );
                          }

                          return Row(
                            children: [
                              Text(
                                'リアクション:',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(width: 8),
                              iconWidget,
                            ],
                          );
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              ),
              FutureBuilder<List<UserModel>>(
                future: api.getNoteReactions(
                  widget.note.id,
                  reaction: reactionKey,
                ),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final users = snap.data ?? [];
                  if (users.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('該当するユーザーはいません'),
                    );
                  }
                  return SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final u = users[i];
                        return ListTile(
                          leading: u.avatarUrl != null
                              ? CircleAvatar(
                                  backgroundImage: CachedNetworkImageProvider(
                                    u.avatarUrl!,
                                  ),
                                )
                              : const CircleAvatar(
                                  child: Icon(Icons.person, size: 20),
                                ),
                          title: Text(u.name),
                          subtitle: Text(u.acct),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            context.push('/profile/${u.id}');
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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
    final settings = ref.watch(settingsProvider);
    // ローカル絵文字マップにノート固有の絵文字（リモート含む）をマージする
    final localEmojiMap = ref.watch(_emojiUrlMapProvider);
    final emojiUrlMap = {
      ...localEmojiMap,
      ...note.emojis,
      ...note.reactionEmojis,
    };

    // リノート（引用なし）の場合
    if (note.text == null && note.renote != null) {
      final activeAccount = ref.read(activeAccountProvider);
      final isMyRenote = activeAccount?.userId == note.user.id;
      return NoteCard(
        note: note.renote!,
        navigatable: widget.navigatable,
        renoteUser: note.user,
        isMyRenote: isMyRenote,
        renoteWrapperNoteId: note.id,
      );
    }

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          widget.renoteUser != null ||
                  note.reply != null ||
                  widget.pinnedByUser != null
              ? 4
              : 12,
          12,
          4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ピン留めヘッダー
            if (widget.pinnedByUser != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_outlined,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.pinnedByUser!.name} がピン留め',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            // リノートヘッダー
            if (widget.renoteUser != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.repeat,
                      size: 14,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${widget.renoteUser!.name} がリノート',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                    if (widget.isMyRenote)
                      _UnrenoteButton(
                        originalNoteId: note.id,
                        renoteWrapperNoteId: widget.renoteWrapperNoteId!,
                      ),
                  ],
                ),
              ),
            // 返信先ヘッダー
            if (note.reply != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Re: ${note.reply!.user.acct}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // ユーザー情報
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push('/profile/${note.user.id}'),
                  child: note.user.avatarUrl != null
                      ? CircleAvatar(
                          radius: settings.avatarRadius,
                          backgroundImage: CachedNetworkImageProvider(
                            note.user.avatarUrl!,
                          ),
                        )
                      : CircleAvatar(
                          radius: settings.avatarRadius,
                          child: Icon(
                            Icons.person,
                            size: settings.avatarRadius,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/profile/${note.user.id}'),
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
                ),
                Text(
                  _formatDateTime(
                    note.createdAt,
                    settings.dateTimeRelative,
                    settings.timezoneOffsetHours,
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

            // CWバー（content warningがある場合）
            if (note.cw != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _cwExpanded = !_cwExpanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note.cw!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _cwExpanded ? '折りたたむ' : '表示',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          _cwExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 本文（MFM レンダリング）
            if (note.text != null && (note.cw == null || _cwExpanded))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: settings.collapseNote
                    ? _CollapsibleNoteContent(
                        maxHeight: 300,
                        contentId: note.text!,
                        child: MfmContent(
                          text: note.text!,
                          emojiUrlMap: emojiUrlMap,
                          style: TextStyle(fontSize: settings.fontSize),
                          enableAnimations: settings.mfmAnimation,
                          onMentionTap: _onMentionTap,
                        ),
                      )
                    : MfmContent(
                        text: note.text!,
                        emojiUrlMap: emojiUrlMap,
                        style: TextStyle(fontSize: settings.fontSize),
                        enableAnimations: settings.mfmAnimation,
                        onMentionTap: _onMentionTap,
                      ),
              ),

            // 引用リノート（quote）がある場合は埋め込み表示
            if (note.renote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _QuotedNote(
                  note: note.renote!,
                  emojiUrlMap: emojiUrlMap,
                  fontSize: settings.fontSize,
                  onMentionTap: _onMentionTap,
                ),
              ),

            // OGPカード（本文にURLが含まれる場合）
            if (note.text != null && (note.cw == null || _cwExpanded))
              Builder(
                builder: (_) {
                  final url = MfmContent.extractFirstUrl(note.text!);
                  if (url == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OgpCard(url: url),
                  );
                },
              ),

            // 添付メディア（CWがある場合は展開時のみ表示）
            if (note.files.isNotEmpty && (note.cw == null || _cwExpanded))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _MediaGrid(files: note.files),
              ),

            // 投票（Poll）がある場合の表示
            if (_localPoll != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(_localPoll!.choices.length, (i) {
                    final choice = _localPoll!.choices[i];
                    final total = _localPoll!.choices.fold<int>(
                      0,
                      (p, e) => p + e.votes,
                    );
                    final pct = total > 0 ? (choice.votes / total) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: _isVoting ? null : () => _handleVote(i),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: choice.isVoted
                                ? Theme.of(context).colorScheme.surfaceVariant
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      choice.text,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${choice.votes}票',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
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
                    final isRemote = _ReactionChip._isRemote(e.key);
                    return _ReactionChip(
                      reactionKey: e.key,
                      count: e.value,
                      isSelected: isSelected,
                      isRemote: isRemote,
                      emojiUrlMap: emojiUrlMap,
                      onTap: isRemote ? null : () => _handleReaction(e.key),
                      onLongPress: () => _showReactionUsers(e.key),
                    );
                  }).toList(),
                ),
              ),

            // アクションボタン
            _ActionBar(
              note: note,
              onReaction: _handleReaction,
              onPinnedChanged: widget.onPinnedChanged,
            ),
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

// ---- 引用ノート埋め込みウィジェット ----
class _QuotedNote extends StatelessWidget {
  final NoteModel note;
  final Map<String, String> emojiUrlMap;
  final double fontSize;
  final void Function(String username, String? host)? onMentionTap;

  const _QuotedNote({
    required this.note,
    this.emojiUrlMap = const {},
    this.fontSize = 14.0,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayNote = (note.text == null && note.renote != null)
        ? note.renote!
        : note;

    return InkWell(
      onTap: () => context.push('/note/${displayNote.id}', extra: displayNote),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                displayNote.user.avatarUrl != null
                    ? CircleAvatar(
                        radius: 12,
                        backgroundImage: CachedNetworkImageProvider(
                          displayNote.user.avatarUrl!,
                        ),
                      )
                    : const CircleAvatar(
                        radius: 12,
                        child: Icon(Icons.person, size: 12),
                      ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayNote.user.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        displayNote.user.acct,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (displayNote.text != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: MfmContent(
                  text: displayNote.text!,
                  emojiUrlMap: emojiUrlMap,
                  style: TextStyle(fontSize: fontSize * 0.95),
                  enableAnimations: false,
                  onMentionTap: onMentionTap,
                ),
              ),
            if (displayNote.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _MediaGrid(files: displayNote.files),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- リアクション Chip（絵文字を画像表示） ----
class _ReactionChip extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool isSelected;
  final bool isRemote;
  final Map<String, String> emojiUrlMap;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ReactionChip({
    required this.reactionKey,
    required this.count,
    required this.isSelected,
    required this.emojiUrlMap,
    required this.onTap,
    this.onLongPress,
    this.isRemote = false,
  });

  /// `:name@.:` → `name@.`、`:name:` → `name`、それ以外は null
  static String? _inner(String key) {
    if (!key.startsWith(':') || !key.endsWith(':')) return null;
    return key.substring(1, key.length - 1);
  }

  /// `@` を含む、かつ `@.` ではない場合はリモート絵文字（リアクション不可）
  /// `:name@.:` はMisskeyがローカル絵文字を示すフォーマットなので押せる
  static bool _isRemote(String key) {
    final inner = _inner(key);
    if (inner == null) return false;
    final atIdx = inner.indexOf('@');
    if (atIdx < 0) return false;
    // `@.` はローカルサーバーを指すため、リモートとは見なさない
    final host = inner.substring(atIdx + 1);
    return host != '.';
  }

  /// Unicode絵文字をtwemoji CDN PNG URLに変換する
  /// 例: ❤️ → https://cdn.../2764-fe0f.png
  static String _twemojiUrl(String emoji) {
    final hex = emoji.runes.map((r) => r.toRadixString(16)).join('-');
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$hex.png';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inner = _inner(reactionKey); // e.g., "name@." or "name" or null
    // リモート対応: フル形式（name@.）で検索し、なければ名前部分のみでフォールバック
    String? imageUrl;
    if (inner != null) {
      imageUrl = emojiUrlMap[inner];
      if (imageUrl == null) {
        final atIdx = inner.indexOf('@');
        final nameOnly = atIdx >= 0 ? inner.substring(0, atIdx) : inner;
        imageUrl = emojiUrlMap[nameOnly];
      }
    }

    final chipWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isRemote
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isSelected && !isRemote
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null)
            Opacity(
              opacity: isRemote ? 0.5 : 1.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 18,
                width: 18,
                fit: BoxFit.contain,
                errorWidget: (context, url, error) =>
                    Text(reactionKey, style: const TextStyle(fontSize: 12)),
              ),
            )
          else
            Opacity(
              opacity: isRemote ? 0.5 : 1.0,
              child: CachedNetworkImage(
                imageUrl: _twemojiUrl(reactionKey),
                height: 18,
                width: 18,
                fit: BoxFit.contain,
                errorWidget: (context, url, error) =>
                    Text(reactionKey, style: const TextStyle(fontSize: 14)),
              ),
            ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: isRemote
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                  : isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: isRemote ? null : onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: chipWidget,
    );
  }
}

// ---- アクションバー ----
class _ActionBar extends ConsumerStatefulWidget {
  final NoteModel note;
  final Future<void> Function(String reaction) onReaction;
  final VoidCallback? onPinnedChanged;

  const _ActionBar({
    required this.note,
    required this.onReaction,
    this.onPinnedChanged,
  });

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _isRenoting = false;

  Future<void> _showNoteMenu(BuildContext context) async {
    final activeAccount = ref.read(activeAccountProvider);
    final isOwn = activeAccount?.userId == widget.note.user.id;
    final api = ref.read(misskeyApiProvider);

    // ノートURLの構築
    final host = activeAccount?.host ?? '';
    final localNoteUrl = host.isNotEmpty
        ? 'https://$host/notes/${widget.note.id}'
        : null;
    // 投稿者がリモートアカウントの場合は uri がリモートURL
    final isRemoteUser = widget.note.user.host.isNotEmpty;
    final remoteNoteUrl = widget.note.uri;

    String _buildReportComment() {
      final buf = StringBuffer();
      if (isRemoteUser && remoteNoteUrl != null) {
        buf.writeln('Note: $remoteNoteUrl');
      }
      if (localNoteUrl != null) {
        buf.writeln('Local Note: $localNoteUrl');
      }
      buf.writeln('-----');
      buf.write('');
      return buf.toString();
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // テキストコピー（全員）
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('テキストをコピー'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final text = widget.note.text ?? '';
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('テキストをコピーしました'),
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
            // 引用してリノート（全員）
            Builder(
              builder: (ctx) {
                final activeAccount = ref.read(activeAccountProvider);
                final canRenote =
                    !((widget.note.visibility ==
                                AppConstants.visibilityFollowers &&
                            widget.note.user.id != activeAccount?.userId) ||
                        widget.note.visibility ==
                            AppConstants.visibilitySpecified);
                return ListTile(
                  leading: const Icon(Icons.format_quote),
                  title: const Text('引用してリノート'),
                  onTap: canRenote
                      ? () {
                          Navigator.pop(sheetCtx);
                          context.push(
                            '/compose',
                            extra: {
                              'renoteId': widget.note.id,
                              'renoteToNote': widget.note,
                            },
                          );
                        }
                      : null,
                );
              },
            ),
            // クリップに追加（全員）
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('クリップに追加'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _addNoteToClip(context);
              },
            ),
            // 削除 / ピン留め（自分の投稿のみ）
            if (isOwn) ...[
              // ピン留め（追加/解除）
              FutureBuilder<UserModel?>(
                future: api?.getMe(),
                builder: (ctx, snap) {
                  final loading = snap.connectionState != ConnectionState.done;
                  final me = snap.data;
                  final isPinned =
                      me?.pinnedNoteIds.contains(widget.note.id) == true;
                  return ListTile(
                    leading: const Icon(Icons.push_pin_outlined),
                    title: Text(
                      loading ? 'ピン留め...' : (isPinned ? 'ピン留め解除' : 'ピン留めに追加'),
                    ),
                    onTap: loading || api == null
                        ? null
                        : () async {
                            Navigator.pop(sheetCtx);
                            try {
                              final me2 = await api.getMe();
                              final currentlyPinned = me2.pinnedNoteIds
                                  .contains(widget.note.id);
                              if (currentlyPinned) {
                                final settings = ref.read(settingsProvider);
                                if (settings.confirmDestructive) {
                                  final confirmed =
                                      await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('ピン留めを解除'),
                                          content: const Text(
                                            'ピン留めを解除してもよろしいですか？',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('キャンセル'),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('解除'),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                  if (!confirmed) return;
                                }

                                await api.unpinNote(widget.note.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ピン留めを解除しました'),
                                    ),
                                  );
                                  widget.onPinnedChanged?.call();
                                  final activeAccount = ref.read(
                                    activeAccountProvider,
                                  );
                                  if (activeAccount != null) {
                                    ref.invalidate(
                                      pinnedNotesProvider(activeAccount.userId),
                                    );
                                  }
                                }
                              } else {
                                await api.pinNote(widget.note.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ピン留めしました')),
                                  );
                                  widget.onPinnedChanged?.call();
                                  final activeAccount = ref.read(
                                    activeAccountProvider,
                                  );
                                  if (activeAccount != null) {
                                    ref.invalidate(
                                      pinnedNotesProvider(activeAccount.userId),
                                    );
                                  }
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('操作に失敗しました: $e')),
                                );
                              }
                            }
                          },
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '削除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteNote(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('削除して再編集'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteAndEdit(context);
                },
              ),
            ],
            // 通報（他人の投稿のみ）
            if (!isOwn)
              ListTile(
                leading: Icon(
                  Icons.flag_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '通報',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => ReportAbuseSheet(
                      userId: widget.note.user.id,
                      initialComment: _buildReportComment(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteNote(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('ノートを削除'),
              content: const Text('このノートを削除しますか？この操作は取り消せません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
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
            content: Text('投稿を削除しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _deleteAndEdit(BuildContext context) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final note = widget.note;
    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('削除して再編集'),
              content: const Text('このノートを削除して再編集しますか？元のノートは削除され、この操作は取り消せません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除して再編集'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    final router = ref.read(routerProvider);
    try {
      await api.deleteNote(note.id);
      router.push(
        '/compose',
        extra: {
          'initialText': note.text ?? '',
          'visibility': note.visibility,
          'initialFiles': note.files,
          'initialCw': note.cw,
          'initialIsSensitive': note.files.any((f) => f.isSensitive),
          if (note.reply != null) 'replyId': note.reply!.id,
          if (note.reply != null) 'replyToNote': note.reply,
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _addNoteToClip(BuildContext context) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    // クリップ一覧を取得
    List<ClipModel> clips;
    try {
      clips = await api.getClips();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('クリップの取得に失敗しました: $e')));
      }
      return;
    }

    if (!context.mounted) return;

    // クリップ一覧ボトムシートを表示
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) =>
          _ClipPickerSheet(clips: clips, noteId: widget.note.id),
    );
  }

  Future<void> _renote() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isRenoting) return;

    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('リノート'),
              content: const Text('このノートをリノートしますか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('リノート'),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted || !confirmed) return;
    }

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
    await widget.onReaction(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeAccount = ref.read(activeAccountProvider);
    final canRenote =
        !((widget.note.visibility == AppConstants.visibilityFollowers &&
                widget.note.user.id != activeAccount?.userId) ||
            widget.note.visibility == AppConstants.visibilitySpecified);
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

class _MediaGrid extends StatefulWidget {
  final List<DriveFileModel> files;

  const _MediaGrid({required this.files});

  @override
  State<_MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<_MediaGrid> {
  final Set<int> _revealedSensitiveIndexes = {};

  Widget _wrapSensitive({
    required DriveFileModel file,
    required int globalIndex,
    required Widget child,
    required VoidCallback onRevealTap,
  }) {
    if (!file.isSensitive || _revealedSensitiveIndexes.contains(globalIndex)) {
      return child;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          Center(
            child: GestureDetector(
              onTap: () =>
                  setState(() => _revealedSensitiveIndexes.add(globalIndex)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.visibility_off, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'センシティブ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 画像グリッド ──
        Builder(
          builder: (_) {
            final imageFiles = files
                .asMap()
                .entries
                .where((e) => e.value.isImage)
                .toList();
            if (imageFiles.isEmpty) return const SizedBox.shrink();
            final count = imageFiles.length.clamp(1, 4);
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count == 1 ? 1 : 2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: count == 1 ? 16 / 9 : 1,
              ),
              itemCount: count,
              itemBuilder: (ctx, i) {
                final entry = imageFiles[i];
                final globalIdx = entry.key;
                final file = entry.value;
                final isRevealed = _revealedSensitiveIndexes.contains(
                  globalIdx,
                );
                final imageWidget = ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: file.thumbnailUrl ?? file.url,
                    fit: BoxFit.cover,
                  ),
                );
                if (file.isSensitive && !isRevealed) {
                  return _wrapSensitive(
                    file: file,
                    globalIndex: globalIdx,
                    child: imageWidget,
                    onRevealTap: () => setState(
                      () => _revealedSensitiveIndexes.add(globalIdx),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute<void>(
                      builder: (_) => _FullscreenImageViewer(
                        urls: imageFiles.map((e) => e.value.url).toList(),
                        initialIndex: i,
                      ),
                    ),
                  ),
                  child: imageWidget,
                );
              },
            );
          },
        ),

        // ── 動画 ──
        ...files.asMap().entries.where((e) => e.value.isVideo).map((entry) {
          final globalIdx = entry.key;
          final f = entry.value;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _wrapSensitive(
              file: f,
              globalIndex: globalIdx,
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
              onRevealTap: () {},
            ),
          );
        }),

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
    final theme = Theme.of(context);
    final popupBg = theme.colorScheme.surface;
    final popupOn = theme.colorScheme.onSurface;

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
        actions: [
          PopupMenuButton<String>(
            color: popupBg,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 8,
            offset: const Offset(0, 8),
            onSelected: (v) {
              if (v == 'download') _downloadCurrent();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ダウンロード',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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

  Future<void> _downloadCurrent() async {
    final url = widget.urls[_current];
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('ダウンロードを開始します...')));
    try {
      final dio = Dio();
      String filename = Uri.tryParse(url)?.pathSegments.last ?? 'file';

      Directory? dir;
      try {
        if (Platform.isAndroid) {
          final dirs = await getExternalStorageDirectories(
            type: StorageDirectory.downloads,
          );
          if (dirs != null && dirs.isNotEmpty) {
            dir = dirs.first;
          } else {
            dir = await getExternalStorageDirectory();
          }
        } else if (Platform.isIOS) {
          dir = await getApplicationDocumentsDirectory();
        } else {
          dir = await getDownloadsDirectory();
          dir ??= await getApplicationDocumentsDirectory();
        }
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }

      final saveFile = File('${dir!.path}${Platform.pathSeparator}$filename');
      final tempFile = File('${saveFile.path}.part');

      await dio.download(url, tempFile.path);
      if (await tempFile.exists()) {
        await tempFile.rename(saveFile.path);
      }

      messenger.showSnackBar(
        SnackBar(content: Text('保存しました: ${saveFile.path}')),
      );
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('ダウンロードに失敗しました')));
    }
  }
}

// ---- リノート解除ボタン ----

class _UnrenoteButton extends ConsumerStatefulWidget {
  final String originalNoteId; // 元ノートのID（API呼び出し用）
  final String renoteWrapperNoteId; // リノートラッパーのID（TL削除用）

  const _UnrenoteButton({
    required this.originalNoteId,
    required this.renoteWrapperNoteId,
  });

  @override
  ConsumerState<_UnrenoteButton> createState() => _UnrenoteButtonState();
}

class _UnrenoteButtonState extends ConsumerState<_UnrenoteButton> {
  bool _isLoading = false;

  Future<void> _unrenote() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isLoading) return;

    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('リノートを解除'),
              content: const Text('このリノートを解除しますか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('解除'),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted || !confirmed) return;
    }

    setState(() => _isLoading = true);
    try {
      await api.unrenote(widget.originalNoteId);
      // TLからリノートラッパーを削除
      for (final type in [
        AppConstants.tabTypeHome,
        AppConstants.tabTypeLocal,
        AppConstants.tabTypeSocial,
        AppConstants.tabTypeGlobal,
      ]) {
        ref
            .read(timelineProvider(type).notifier)
            .removeNote(widget.renoteWrapperNoteId);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('リノートを解除しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('リノート解除に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : GestureDetector(
            onTap: _unrenote,
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: 'リノートを解除',
              child: Icon(
                Icons.repeat_one_outlined,
                size: 14,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
  }
}

// ---- 省略表示ウィジェット ----

class _CollapsibleNoteContent extends StatefulWidget {
  final Widget child;
  final double maxHeight;
  final String contentId;

  const _CollapsibleNoteContent({
    required this.child,
    required this.maxHeight,
    required this.contentId,
  });

  @override
  State<_CollapsibleNoteContent> createState() =>
      _CollapsibleNoteContentState();
}

class _CollapsibleNoteContentState extends State<_CollapsibleNoteContent> {
  final _scrollController = ScrollController();
  bool _expanded = false;
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _scheduleOverflowCheck();
  }

  @override
  void didUpdateWidget(_CollapsibleNoteContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentId != widget.contentId) {
      _expanded = false;
      _overflows = false;
      _scheduleOverflowCheck();
    }
  }

  void _scheduleOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        setState(() => _overflows = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.child,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _expanded = false),
              child: const Text('折りたたむ'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: widget.child,
              ),
            ),
            if (_overflows)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (theme.cardTheme.color ??
                                  theme.colorScheme.surfaceContainerLow)
                              .withValues(alpha: 0),
                          theme.cardTheme.color ??
                              theme.colorScheme.surfaceContainerLow,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_overflows)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _expanded = true),
              child: const Text('続きを読む'),
            ),
          ),
      ],
    );
  }
}
// ---- クリップ選択ボトムシート ----

class _ClipPickerSheet extends ConsumerStatefulWidget {
  final List<ClipModel> clips;
  final String noteId;

  const _ClipPickerSheet({required this.clips, required this.noteId});

  @override
  ConsumerState<_ClipPickerSheet> createState() => _ClipPickerSheetState();
}

class _ClipPickerSheetState extends ConsumerState<_ClipPickerSheet> {
  late List<ClipModel> _clips;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _clips = List.from(widget.clips);
  }

  Future<void> _addToClip(ClipModel clip) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await api.addNoteToClip(clipId: clip.id, noteId: widget.noteId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「${clip.name}」に追加しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _createAndAdd() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isProcessing) return;

    final nameController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいクリップを作成'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'タイトル',
            hintText: 'クリップのタイトルを入力',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('作成して追加'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final clip = await api.createClip(name: name);
      await api.addNoteToClip(clipId: clip.id, noteId: widget.noteId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「${clip.name}」に追加しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.bookmark_add_outlined),
                const SizedBox(width: 8),
                Text('クリップに追加', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isProcessing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('新しいクリップを作成'),
            onTap: _isProcessing ? null : _createAndAdd,
          ),
          if (_clips.isNotEmpty) const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _clips.length,
              itemBuilder: (ctx, i) {
                final clip = _clips[i];
                return ListTile(
                  leading: Icon(
                    clip.isPublic ? Icons.bookmark : Icons.bookmark_outline,
                  ),
                  title: Text(clip.name),
                  subtitle: clip.description != null
                      ? Text(
                          clip.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: _isProcessing ? null : () => _addToClip(clip),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
