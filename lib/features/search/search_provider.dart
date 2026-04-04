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

  const NoteSearchState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
  });

  NoteSearchState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? query,
  }) => NoteSearchState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
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
    state = NoteSearchState(isLoading: true, query: query);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotes(query: query);
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
    state = const NoteSearchState();
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
