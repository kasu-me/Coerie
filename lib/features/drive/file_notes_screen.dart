import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';

class DriveFileNotesScreen extends ConsumerStatefulWidget {
  final DriveFileModel file;

  const DriveFileNotesScreen({super.key, required this.file});

  @override
  ConsumerState<DriveFileNotesScreen> createState() =>
      _DriveFileNotesScreenState();
}

class _DriveFileNotesScreenState extends ConsumerState<DriveFileNotesScreen> {
  final List<NoteModel> _notes = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchNotes());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoadingMore &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _fetchNotes(loadMore: true);
    }
  }

  Future<void> _fetchNotes({bool loadMore = false}) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _error = 'ログインが必要です');
      return;
    }

    if (loadMore) {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final untilId = loadMore && _notes.isNotEmpty ? _notes.last.id : null;

    try {
      final notes = await api.getNotesByFile(
        fileId: widget.file.id,
        limit: 20,
        untilId: untilId,
      );
      setState(() {
        if (loadMore) {
          _notes.addAll(notes);
          _isLoadingMore = false;
        } else {
          _notes.clear();
          _notes.addAll(notes);
          _isLoading = false;
        }
        _hasMore = notes.length >= 20;
      });
    } on DioError catch (dioErr) {
      // 400 が返るサーバでは file:ID 検索をサポートしていないことがあるため
      // 代替としてファイル名で検索を試みる
      if (dioErr.response?.statusCode == 400) {
        try {
          final notes = await api.searchNotes(
            query: widget.file.name,
            limit: 20,
            untilId: untilId,
          );
          setState(() {
            if (loadMore) {
              _notes.addAll(notes);
              _isLoadingMore = false;
            } else {
              _notes.clear();
              _notes.addAll(notes);
              _isLoading = false;
            }
            _hasMore = notes.length >= 20;
          });
          if (!loadMore && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ファイルIDでの検索に対応していないため、ファイル名で代替検索しました'),
              ),
            );
          }
        } catch (e) {
          setState(() {
            _error = 'サーバーでの検索に失敗しました';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } else {
        setState(() {
          _error = dioErr.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _fetchNotes(loadMore: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('「${widget.file.name}」を添付したノート')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _fetchNotes, child: const Text('再試行')),
          ],
        ),
      );
    }

    if (_isLoading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLoading && _notes.isEmpty) {
      return const Center(child: Text('該当するノートがありません'));
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _notes.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _notes.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = _notes[index];
          return NoteCard(key: ValueKey(note.id), note: note);
        },
      ),
    );
  }
}
