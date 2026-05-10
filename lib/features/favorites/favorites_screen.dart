import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  List<NoteModel> _notes = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();

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
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final notes = await api.getFavorites(limit: 20);
      if (mounted) {
        setState(() {
          _notes = notes;
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
      final more = await api.getFavorites(limit: 20, untilId: _oldestNoteId);
      if (mounted) {
        setState(() {
          _notes = [..._notes, ...more];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入り'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('エラーが発生しました: $_error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    if (_notes.isEmpty) {
      return const Center(child: Text('お気に入りがありません'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _notes.length + (_isLoading || _hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _notes.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = _notes[index];
          return NoteCard(
            key: ValueKey(note.id),
            note: note,
            onUnfavorited: () {
              if (mounted) {
                setState(() => _notes.removeWhere((n) => n.id == note.id));
              }
            },
          );
        },
      ),
    );
  }
}
