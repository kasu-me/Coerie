import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/errors/api_error_message.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/mixins/infinite_scroll_mixin.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/paged_notifier.dart';
import '../../shared/widgets/error_view.dart';
import '../timeline/widgets/note_card.dart';

typedef _FileKey = ({String id, String name});

class _FileNotesNotifier extends PagedNotifier<NoteModel> {
  final Ref _ref;
  final _FileKey file;

  /// `file:ID` 検索が使えずファイル名での代替検索に切り替えたか。
  /// 画面側が初回だけ案内を出すために見る。
  bool usedNameFallback = false;

  _FileNotesNotifier(this._ref, this.file) {
    fetch();
  }

  @override
  String get errorFallback => 'ノートを取得できませんでした';

  @override
  String cursorOf(NoteModel item) => item.id;

  @override
  Future<List<NoteModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];

    try {
      return await api.getNotesByFile(
        fileId: file.id,
        limit: pageSize,
        untilId: untilId,
      );
    } on DioException catch (e) {
      // 400 を返すサーバーは file:ID での検索に対応していないため、
      // ファイル名での検索で代替する。それ以外の失敗は通常のエラー扱い。
      if (e.response?.statusCode != 400) rethrow;
      try {
        final notes = await api.searchNotes(
          query: file.name,
          limit: pageSize,
          untilId: untilId,
        );
        usedNameFallback = true;
        return notes;
      } catch (_) {
        throw const AppException('サーバーでの検索に失敗しました');
      }
    }
  }
}

final _fileNotesProvider = StateNotifierProvider.autoDispose
    .family<_FileNotesNotifier, PagedState<NoteModel>, _FileKey>(
      (ref, file) => _FileNotesNotifier(ref, file),
    );

class DriveFileNotesScreen extends ConsumerStatefulWidget {
  final DriveFileModel file;

  const DriveFileNotesScreen({super.key, required this.file});

  @override
  ConsumerState<DriveFileNotesScreen> createState() =>
      _DriveFileNotesScreenState();
}

class _DriveFileNotesScreenState extends ConsumerState<DriveFileNotesScreen>
    with InfiniteScrollMixin<DriveFileNotesScreen> {
  /// 代替検索の案内を出したか（1回だけ出す）。
  bool _notifiedFallback = false;

  _FileKey get _key => (id: widget.file.id, name: widget.file.name);

  @override
  void onLoadMore() =>
      ref.read(_fileNotesProvider(_key).notifier).fetch(loadMore: true);

  /// ファイル名での代替検索に切り替わっていたら、一度だけ理由を伝える。
  void _notifyFallbackOnce() {
    if (_notifiedFallback) return;
    if (!ref.read(_fileNotesProvider(_key).notifier).usedNameFallback) return;
    _notifiedFallback = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ファイルIDでの検索に対応していないため、ファイル名で代替検索しました')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_fileNotesProvider(_key), (_, _) => _notifyFallbackOnce());
    final state = ref.watch(_fileNotesProvider(_key));

    return Scaffold(
      appBar: AppBar(title: Text('「${widget.file.name}」を添付したノート')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(PagedState<NoteModel> state) {
    final notifier = ref.read(_fileNotesProvider(_key).notifier);

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error!, onRetry: notifier.refresh);
    }
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('該当するノートがありません'));
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = state.items[index];
          return NoteCard(key: ValueKey(note.id), note: note);
        },
      ),
    );
  }
}
