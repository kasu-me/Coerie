import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/misskey_api_provider.dart';

// ---- 検索エラー種別 ----

enum SearchErrorType { disabled, network, unknown }

class SearchError {
  final SearchErrorType type;
  final String message;

  const SearchError({required this.type, required this.message});
}

// ---- ノート検索（notes/search）----

class NoteSearchState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String query;
  // 投稿日時の期間フィルタ（日単位・null なら未指定）
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  const NoteSearchState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
    this.rangeStart,
    this.rangeEnd,
  });

  NoteSearchState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? query,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    bool clearRange = false,
  }) => NoteSearchState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
    rangeStart: clearRange ? null : (rangeStart ?? this.rangeStart),
    rangeEnd: clearRange ? null : (rangeEnd ?? this.rangeEnd),
  );
}

final noteSearchProvider =
    StateNotifierProvider<NoteSearchNotifier, NoteSearchState>(
      (ref) => NoteSearchNotifier(ref),
    );

class NoteSearchNotifier extends StateNotifier<NoteSearchState> {
  final Ref _ref;

  NoteSearchNotifier(this._ref) : super(const NoteSearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    // 期間フィルタは検索をまたいで保持する
    state = NoteSearchState(
      isLoading: true,
      query: query,
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
    );
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotes(
        query: query,
        rangeStartAt: _rangeStartAt(),
        rangeEndAt: _rangeEndAt(),
      );
      state = state.copyWith(
        notes: notes,
        isLoading: false,
        hasMore: notes.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.notes.isEmpty) return;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotes(
        query: state.query,
        untilId: state.notes.last.id,
        rangeStartAt: _rangeStartAt(),
        rangeEndAt: _rangeEndAt(),
      );
      state = state.copyWith(
        notes: [...state.notes, ...notes],
        isLoading: false,
        hasMore: notes.length >= 20,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  /// 期間フィルタを設定する。日単位指定のため下限はその日の 00:00:00.000、
  /// 上限はその日の 23:59:59.999 に丸めて API へ渡す。
  /// start/end がともに null の場合は範囲解除。
  /// query が入力済みなら同条件で即再検索する。
  void setDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) {
      state = state.copyWith(clearRange: true);
    } else {
      state = state.copyWith(rangeStart: start, rangeEnd: end);
    }
    if (state.query.trim().isNotEmpty) {
      search(state.query);
    }
  }

  /// rangeStart をその日の始まり（00:00:00.000）のエポックミリ秒に変換する。
  int? _rangeStartAt() {
    final s = state.rangeStart;
    if (s == null) return null;
    return DateTime(s.year, s.month, s.day).millisecondsSinceEpoch;
  }

  /// rangeEnd をその日の終わり（23:59:59.999）のエポックミリ秒に変換する。
  int? _rangeEndAt() {
    final e = state.rangeEnd;
    if (e == null) return null;
    return DateTime(
      e.year,
      e.month,
      e.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
  }

  void clear() {
    // 検索結果はクリアするが、期間フィルタ（rangeStart/rangeEnd）は保持する。
    // 範囲の完全解除はチップの × から setDateRange(null, null) で行う。
    state = NoteSearchState(
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
    );
  }
}

// ---- タグ検索（notes/search-by-tag）----

class TagNoteSearchState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String tag;

  const TagNoteSearchState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.tag = '',
  });

  TagNoteSearchState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? tag,
  }) => TagNoteSearchState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    tag: tag ?? this.tag,
  );
}

final tagNoteSearchProvider =
    StateNotifierProvider<TagNoteSearchNotifier, TagNoteSearchState>(
      (ref) => TagNoteSearchNotifier(ref),
    );

class TagNoteSearchNotifier extends StateNotifier<TagNoteSearchState> {
  final Ref _ref;

  TagNoteSearchNotifier(this._ref) : super(const TagNoteSearchState());

  Future<void> search(String tag) async {
    final trimmed = tag.trim().replaceAll('#', '');
    if (trimmed.isEmpty) return;
    state = TagNoteSearchState(isLoading: true, tag: trimmed);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotesByTag(tag: trimmed);
      state = state.copyWith(
        notes: notes,
        isLoading: false,
        hasMore: notes.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.notes.isEmpty) return;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotesByTag(
        tag: state.tag,
        untilId: state.notes.last.id,
      );
      state = state.copyWith(
        notes: [...state.notes, ...notes],
        isLoading: false,
        hasMore: notes.length >= 20,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  void clear() {
    state = const TagNoteSearchState();
  }
}

// ---- ユーザー検索（users/search）----

class UserSearchState {
  final List<UserModel> users;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String query;

  const UserSearchState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
  });

  UserSearchState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? query,
  }) => UserSearchState(
    users: users ?? this.users,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
  );
}

final userSearchProvider =
    StateNotifierProvider<UserSearchNotifier, UserSearchState>(
      (ref) => UserSearchNotifier(ref),
    );

class UserSearchNotifier extends StateNotifier<UserSearchState> {
  final Ref _ref;

  UserSearchNotifier(this._ref) : super(const UserSearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    state = UserSearchState(isLoading: true, query: query);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final users = await api.searchUsers(query: query);
      state = state.copyWith(
        users: users,
        isLoading: false,
        hasMore: users.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.users.isEmpty) return;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final users = await api.searchUsers(
        query: state.query,
        offset: state.users.length,
      );
      state = state.copyWith(
        users: [...state.users, ...users],
        isLoading: false,
        hasMore: users.length >= 20,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  void clear() {
    state = const UserSearchState();
  }
}

// ---- ハッシュタグ検索（hashtags/search）----

class HashtagSearchState {
  final List<String> hashtags;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String query;

  const HashtagSearchState({
    this.hashtags = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
  });

  HashtagSearchState copyWith({
    List<String>? hashtags,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? query,
  }) => HashtagSearchState(
    hashtags: hashtags ?? this.hashtags,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
  );
}

final hashtagSearchProvider =
    StateNotifierProvider<HashtagSearchNotifier, HashtagSearchState>(
      (ref) => HashtagSearchNotifier(ref),
    );

class HashtagSearchNotifier extends StateNotifier<HashtagSearchState> {
  final Ref _ref;

  HashtagSearchNotifier(this._ref) : super(const HashtagSearchState());

  Future<void> search(String query) async {
    final trimmed = query.trim().replaceAll('#', '');
    if (trimmed.isEmpty) return;
    state = HashtagSearchState(isLoading: true, query: trimmed);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final tags = await api.searchHashtags(query: trimmed);
      state = state.copyWith(
        hashtags: tags,
        isLoading: false,
        hasMore: tags.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.hashtags.isEmpty) return;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final tags = await api.searchHashtags(
        query: state.query,
        offset: state.hashtags.length,
      );
      state = state.copyWith(
        hashtags: [...state.hashtags, ...tags],
        isLoading: false,
        hasMore: tags.length >= 20,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  void clear() {
    state = const HashtagSearchState();
  }
}

// ---- エラー解析ヘルパー ----

SearchError _parseDioError(DioException e) {
  final statusCode = e.response?.statusCode;
  final data = e.response?.data;
  if (statusCode == 400 || statusCode == 403) {
    // Misskey はサーバー側で無効な機能に対して 400 や "UNAVAILABLE" エラーを返す
    String errorCode = '';
    if (data is Map) {
      final errorObj = data['error'];
      if (errorObj is Map) errorCode = (errorObj['code'] as String?) ?? '';
    }
    if (errorCode == 'UNAVAILABLE' ||
        errorCode.contains('DISABLED') ||
        errorCode.contains('NOT_SUPPORTED')) {
      return SearchError(
        type: SearchErrorType.disabled,
        message: 'この機能はサーバーで無効になっています',
      );
    }
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError) {
    return const SearchError(
      type: SearchErrorType.network,
      message: 'ネットワークエラーが発生しました',
    );
  }
  return SearchError(
    type: SearchErrorType.unknown,
    message: e.message ?? '不明なエラーが発生しました',
  );
}

// ---- ノート検索の事前有効性判定 ----

/// ノート検索がサーバーで有効かどうか（事前判定用）。
/// 取得できない場合は true（実行時エラー処理にフォールバック）。
///
/// misskeyApiProvider はアカウント切替時に再生成されるため、
/// これを watch していれば切替時に自動で再評価される。
final canSearchNotesProvider = FutureProvider<bool>((ref) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return true;
  return api.fetchCanSearchNotes();
});
