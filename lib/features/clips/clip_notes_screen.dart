import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/providers/account_provider.dart';
import '../../data/models/clip_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';

class ClipNotesScreen extends ConsumerStatefulWidget {
  final ClipModel clip;
  final String? host;

  const ClipNotesScreen({super.key, required this.clip, this.host});

  @override
  ConsumerState<ClipNotesScreen> createState() => _ClipNotesScreenState();
}

class _ClipNotesScreenState extends ConsumerState<ClipNotesScreen> {
  List<NoteModel> _notes = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  // false: newest first（降順）, true: oldest first（昇順）
  bool _ascending = false;
  final _scrollController = ScrollController();

  void _sortNotes() {
    _notes.sort(
      (a, b) => _ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt),
    );
  }

  /// ページネーション用に常に最古ノートのIDを返す
  String? get _oldestNoteId {
    if (_notes.isEmpty) return null;
    return _notes
        .reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b)
        .id;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoading &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _notes = [];
      _hasMore = true;
      _error = null;
      _isLoading = true;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.getClipNotes(clipId: widget.clip.id, limit: 20);
      if (mounted) {
        setState(() {
          _notes = notes;
          _sortNotes();
          _hasMore = notes.length >= 20;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_notes.isEmpty) return;
    setState(() => _isLoading = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final more = await api.getClipNotes(
        clipId: widget.clip.id,
        limit: 20,
        untilId: _oldestNoteId,
      );
      if (mounted) {
        setState(() {
          _notes.addAll(more);
          _sortNotes();
          _hasMore = more.length >= 20;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('読み込みに失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 昇順切り替え時に未読込の古いノートを全て取得する
  Future<void> _ensureAllLoaded() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    setState(() => _isLoading = true);
    try {
      while (_hasMore) {
        final more = await api.getClipNotes(
          clipId: widget.clip.id,
          limit: 100,
          untilId: _oldestNoteId,
        );
        if (!mounted) return;
        setState(() {
          _notes.addAll(more);
          _hasMore = more.length >= 100;
        });
        if (more.isEmpty) break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('読み込みに失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sortNotes();
          _isLoading = false;
        });
      }
    }
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
      setState(() => _notes.removeWhere((n) => n.id == note.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('クリップから削除しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _openInBrowser() async {
    final active = ref.read(activeAccountProvider);
    final host = widget.host ?? active?.host;
    if (host == null || host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ホストが指定されていません')));
      }
      return;
    }
    final uri = Uri.parse('https://$host/clips/${widget.clip.id}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ブラウザを開けませんでした')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.clip.name,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.clip.description != null)
              Text(
                widget.clip.description!,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _ascending ? '古い順（昇順）' : '新しい順（降順）',
            onPressed: _isLoading
                ? null
                : () async {
                    final toAscending = !_ascending;
                    setState(() => _ascending = toAscending);
                    if (toAscending && _hasMore) {
                      // 未読込の古いノートを全て取得してから昇順表示
                      await _ensureAllLoaded();
                    } else {
                      setState(() => _sortNotes());
                    }
                  },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'open_browser') _openInBrowser();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'open_browser',
                child: Text('ブラウザで開く'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(bottom: true, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('エラーが発生しました', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_notes.isEmpty) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _notes.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _notes.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = _notes[i];
          return NoteCard(
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
