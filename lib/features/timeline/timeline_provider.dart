import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../core/constants/app_constants.dart';

// 各タイムラインの状態
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

// タイムラインタイプ別のプロバイダー
final timelineProvider =
    StateNotifierProviderFamily<TimelineNotifier, TimelineState, String>(
      (ref, timelineType) => TimelineNotifier(ref, timelineType),
    );

class TimelineNotifier extends StateNotifier<TimelineState> {
  final String timelineType;

  TimelineNotifier(Ref ref, this.timelineType) : super(const TimelineState()) {
    fetchNotes();
  }

  Future<void> fetchNotes({bool loadMore = false}) async {
    if (loadMore) {
      if (state.isLoadingMore) return;
      state = state.copyWith(isLoadingMore: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    // TODO: 実際のAPIコールに置き換える
    // final account = _ref.read(activeAccountProvider);
    // if (account == null) { ... }
    // final dio = Dio();
    // final endpoint = _getEndpoint(timelineType);
    // final response = await dio.post(
    //   'https://${account.host}/api/$endpoint',
    //   data: {'i': account.token, 'limit': 20, ...},
    // );
    // final notes = (response.data as List)
    //   .map((n) => NoteModel.fromJson(n, host: account.host))
    //   .toList();

    await Future.delayed(const Duration(milliseconds: 500));

    if (loadMore) {
      state = state.copyWith(isLoadingMore: false, notes: [...state.notes]);
    } else {
      state = state.copyWith(isLoading: false, notes: []);
    }
  }

  String getEndpoint(String type) {
    return switch (type) {
      AppConstants.tabTypeHome => 'notes/timeline',
      AppConstants.tabTypeLocal => 'notes/local-timeline',
      AppConstants.tabTypeSocial => 'notes/hybrid-timeline',
      AppConstants.tabTypeGlobal => 'notes/global-timeline',
      _ => 'notes/timeline',
    };
  }
}
