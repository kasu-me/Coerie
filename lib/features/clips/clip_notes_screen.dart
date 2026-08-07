import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/errors/api_error_message.dart';
import '../../shared/providers/account_provider.dart';
import '../../data/models/clip_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/mixins/infinite_scroll_mixin.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/paged_notifier.dart';
import '../timeline/widgets/note_card.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/error_view.dart';

/// クリップの中身。
///
/// 保持する順序は API の返却順（新しい順）のまま固定し、昇順・降順の
/// 並べ替えは画面側で行う。ここで並べ替えてしまうと、昇順のとき
/// [PagedNotifier] がカーソルに使う末尾要素が「最も新しいノート」になり、
/// 追加読み込みが同じページを取り続ける。
class _ClipNotesNotifier extends PagedNotifier<NoteModel> {
  final Ref _ref;
  final String clipId;

  _ClipNotesNotifier(this._ref, this.clipId) {
    fetch();
  }

  @override
  String get errorFallback => 'クリップの中身を取得できませんでした';

  @override
  String cursorOf(NoteModel item) => item.id;

  @override
  Future<List<NoteModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];
    return api.getClipNotes(clipId: clipId, limit: pageSize, untilId: untilId);
  }

  /// 未取得の古いノートをすべて読み込む（昇順表示への切り替え時に使う）。
  ///
  /// 昇順ではリストの末尾が最古のノートになるため、全件揃っていないと
  /// 表示順が途中で破綻する。エラーが出た時点で打ち切る。
  Future<void> fetchAll() async {
    while (state.hasMore && state.error == null) {
      final countBefore = state.items.length;
      await fetch(loadMore: true);
      // 途中で refresh() が入ると fetch() は結果を捨てて即座に返る。
      // hasMore は真のままなので、件数が増えなければ打ち切らないと空回りする。
      if (state.items.length == countBefore) break;
    }
  }

  /// 一覧から1件取り除く（クリップから削除した直後の反映用）。再取得はしない。
  void removeLocally(String noteId) {
    state = state.copyWith(
      items: state.items.where((n) => n.id != noteId).toList(),
    );
  }
}

final _clipNotesProvider = StateNotifierProvider.autoDispose
    .family<_ClipNotesNotifier, PagedState<NoteModel>, String>(
      (ref, clipId) => _ClipNotesNotifier(ref, clipId),
    );

class ClipNotesScreen extends ConsumerStatefulWidget {
  final ClipModel clip;
  final String? host;

  const ClipNotesScreen({super.key, required this.clip, this.host});

  @override
  ConsumerState<ClipNotesScreen> createState() => _ClipNotesScreenState();
}

class _ClipNotesScreenState extends ConsumerState<ClipNotesScreen>
    with InfiniteScrollMixin<ClipNotesScreen> {
  /// お気に入り状態を含む最新のクリップ。画面を閉じるときに呼び出し元へ返す。
  late ClipModel _clip = widget.clip;
  bool _isTogglingFavorite = false;

  // false: newest first（降順）, true: oldest first（昇順）
  bool _ascending = false;

  _ClipNotesNotifier get _notifier =>
      ref.read(_clipNotesProvider(widget.clip.id).notifier);

  @override
  void onLoadMore() => _notifier.fetch(loadMore: true);

  /// 表示順に並べ替えたノート。保持順（API の返却順）は変えない。
  List<NoteModel> _sorted(List<NoteModel> notes) => [...notes]
    ..sort(
      (a, b) => _ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt),
    );

  Future<void> _toggleSortOrder(bool hasMore) async {
    final toAscending = !_ascending;
    setState(() => _ascending = toAscending);
    // 昇順は全件揃っていないと表示順が破綻するため、先に読み切る。
    if (toAscending && hasMore) await _notifier.fetchAll();
  }

  /// 再読み込み。
  ///
  /// [PagedNotifier.refresh] は先頭1ページだけ取り直すため、昇順のまま呼ぶと
  /// 「最新ページの中で最も古いノート」が先頭に来て順序が崩れて見える。
  /// 昇順表示中は切り替え時と同じく全件読み切ってから表示する。
  Future<void> _refresh() async {
    await _notifier.refresh();
    if (_ascending && mounted) await _notifier.fetchAll();
  }

  Future<void> _removeNote(NoteModel note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('クリップから削除'),
        content: const Text('このノートをクリップから削除しますか？'),
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
    );
    if (confirmed != true || !mounted) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.removeNoteFromClip(clipId: widget.clip.id, noteId: note.id);
      _notifier.removeLocally(note.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('クリップから削除しました')));
      }
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
      }
    }
  }

  /// クリップのお気に入り登録・解除を切り替える
  Future<void> _toggleFavorite() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null || _isTogglingFavorite) return;
    final wasFavorited = _clip.isFavorited ?? false;

    setState(() => _isTogglingFavorite = true);
    try {
      if (wasFavorited) {
        await api.unfavoriteClip(_clip.id);
      } else {
        await api.favoriteClip(_clip.id);
      }
      if (!mounted) return;
      final count = (_clip.favoritedCount ?? 0) + (wasFavorited ? -1 : 1);
      setState(() {
        _clip = _clip.copyWith(
          isFavorited: !wasFavorited,
          favoritedCount: count < 0 ? 0 : count,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasFavorited ? 'お気に入りから削除しました' : 'お気に入りに追加しました'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apiErrorMessage(
                e,
                fallback: wasFavorited ? 'お気に入りの解除に失敗しました' : 'お気に入りの登録に失敗しました',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  String? get _clipUrl {
    final host = widget.host ?? ref.read(activeAccountProvider)?.host;
    if (host == null || host.isEmpty) return null;
    return 'https://$host/clips/${widget.clip.id}';
  }

  void _shareAsNote() {
    final url = _clipUrl;
    if (url == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ホストが指定されていません')));
      return;
    }
    context.push('/compose', extra: {'initialText': '${_clip.name}\n$url'});
  }

  Future<void> _openInBrowser() async {
    final url = _clipUrl;
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ホストが指定されていません')));
      }
      return;
    }
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ブラウザを開けませんでした')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_clipNotesProvider(widget.clip.id));
    final isFavorited = _clip.isFavorited ?? false;
    // お気に入り状態の変化を一覧画面へ返すため、戻る操作を自前で処理する
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_clip);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _clip.name,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              if (_clip.description != null)
                Text(
                  _clip.description!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(isFavorited ? Icons.star : Icons.star_border),
              tooltip: isFavorited ? 'お気に入りから削除' : 'お気に入りに追加',
              onPressed: _isTogglingFavorite ? null : _toggleFavorite,
            ),
            IconButton(
              icon: Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              tooltip: _ascending ? '古い順（昇順）' : '新しい順（降順）',
              onPressed: state.isLoading
                  ? null
                  : () => _toggleSortOrder(state.hasMore),
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'open_browser':
                    _openInBrowser();
                  case 'share_note':
                    _shareAsNote();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'open_browser',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser),
                      SizedBox(width: 8),
                      Text('ブラウザで開く'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share_note',
                  child: Row(
                    children: [
                      Icon(Icons.edit_note),
                      SizedBox(width: 8),
                      Text('ノートで共有'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(bottom: true, child: _buildBody(state)),
      ),
    );
  }

  Widget _buildBody(PagedState<NoteModel> state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return ErrorView(message: state.error!, onRetry: _refresh);
    }
    if (state.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('ノートがありません'),
            SizedBox(height: 8),
            Text('ノートのメニューからクリップに追加できます', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final notes = _sorted(state.items);
    // 追加読み込みぶんは常に「より古いノート」なので、昇順では先頭側に入る。
    // インジケーターも同じ側に置かないと、続きが下にあるように見えてしまう。
    final loaderIndex = state.hasMore ? (_ascending ? 0 : notes.length) : -1;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: notes.length + (state.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == loaderIndex) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = notes[loaderIndex == 0 ? i - 1 : i];
          return NoteCard(
            key: ValueKey(note.id),
            note: note,
            trailing: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'クリップから削除',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _removeNote(note),
                  child: Icon(
                    Icons.bookmark_remove,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
