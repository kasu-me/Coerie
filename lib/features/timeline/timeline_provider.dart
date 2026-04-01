import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/streaming/streaming_service.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';

class TimelineState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const TimelineState({
    this.notes = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  TimelineState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) => TimelineState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: error,
  );
}

final timelineProvider =
    StateNotifierProviderFamily<TimelineNotifier, TimelineState, String>(
      (ref, timelineType) => TimelineNotifier(ref, timelineType),
    );

class TimelineNotifier extends StateNotifier<TimelineState> {
  final Ref _ref;
  final String timelineType;
  StreamSubscription<NoteUpdateEvent>? _noteUpdateSub;

  TimelineNotifier(this._ref, this.timelineType)
    : super(const TimelineState()) {
    fetchNotes();
    // アカウント切り替え時にTLをリセット＆再取得
    _ref.listen(activeAccountProvider, (prev, next) {
      if (prev?.id != next?.id) {
        state = const TimelineState();
        fetchNotes();
      }
    });
    // ストリーミングサービスの削除イベントを購読
    _subscribeNoteUpdates(_ref.read(streamingServiceProvider));
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _noteUpdateSub?.cancel();
      _subscribeNoteUpdates(next);
    });
  }

  void _subscribeNoteUpdates(StreamingService? streaming) {
    if (streaming == null) return;
    _noteUpdateSub = streaming.noteUpdateStream.listen((event) {
      if (event.type == 'deleted') {
        removeNote(event.noteId);
      }
    });
  }

  @override
  void dispose() {
    _noteUpdateSub?.cancel();
    super.dispose();
  }

  String getEndpoint(String type) {
    if (type.startsWith('list:')) return 'notes/user-list-timeline';
    if (type.startsWith('antenna:')) return 'antennas/notes';
    return switch (type) {
      AppConstants.tabTypeHome => 'notes/timeline',
      AppConstants.tabTypeLocal => 'notes/local-timeline',
      AppConstants.tabTypeSocial => 'notes/hybrid-timeline',
      AppConstants.tabTypeGlobal => 'notes/global-timeline',
      _ => 'notes/timeline',
    };
  }

  Map<String, dynamic> getExtraParams(String type) {
    if (type.startsWith('list:')) return {'listId': type.substring(5)};
    if (type.startsWith('antenna:')) return {'antennaId': type.substring(8)};
    return {};
  }

  Future<void> fetchNotes({bool loadMore = false}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) {
      state = state.copyWith(isLoading: false, error: 'ログインが必要です');
      return;
    }

    if (loadMore) {
      if (state.isLoadingMore) return;
      state = state.copyWith(isLoadingMore: true, error: null);
    } else {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final endpoint = getEndpoint(timelineType);
      final extraParams = getExtraParams(timelineType);
      final untilId = loadMore && state.notes.isNotEmpty
          ? state.notes.last.id
          : null;
      final notes = await api.getTimeline(
        endpoint: endpoint,
        limit: 20,
        untilId: untilId,
        extraParams: extraParams,
      );

      if (loadMore) {
        state = state.copyWith(
          isLoadingMore: false,
          notes: [...state.notes, ...notes],
        );
      } else {
        state = state.copyWith(isLoading: false, notes: notes);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> refresh() async {
    await fetchNotes();
  }

  void prependNote(NoteModel note) {
    // 重複チェック
    if (state.notes.any((n) => n.id == note.id)) return;
    state = state.copyWith(notes: [note, ...state.notes]);
  }

  Future<List<NoteModel>> fetchNew() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null || state.notes.isEmpty) return [];

    try {
      final endpoint = getEndpoint(timelineType);
      final extraParams = getExtraParams(timelineType);
      final sinceId = state.notes.first.id;
      final newNotes = await api.getTimeline(
        endpoint: endpoint,
        limit: 20,
        sinceId: sinceId,
        extraParams: extraParams,
      );
      if (newNotes.isNotEmpty) {
        // WebSocket の prependNote と競合した場合の重複を除去
        final existingIds = state.notes.map((n) => n.id).toSet();
        final unique = newNotes
            .where((n) => !existingIds.contains(n.id))
            .toList();
        if (unique.isNotEmpty) {
          state = state.copyWith(notes: [...unique, ...state.notes]);
        }
      }
      return newNotes;
    } catch (_) {
      return [];
    }
  }

  void removeNote(String noteId) {
    state = state.copyWith(
      notes: state.notes.where((n) => n.id != noteId).toList(),
    );
  }
}
