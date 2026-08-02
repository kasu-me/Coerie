import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';
import '../../data/remote/misskey_api.dart';
import '../../shared/providers/misskey_api_provider.dart';

// ---- 検索エラー種別 ----

enum SearchErrorType { disabled, network, unknown }

class SearchError {
  final SearchErrorType type;
  final String message;

  const SearchError({required this.type, required this.message});
}

// ---- ノート検索（notes/search）----

/// ノート検索の検索対象。
/// all: 全サーバー / local: ローカルのみ / server: 指定サーバー / user: 指定ユーザー
enum NoteSearchScope { all, local, server, user }

class NoteSearchState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String query;
  // 投稿日時の期間フィルタ（日単位・null なら未指定）
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  // 検索対象の絞り込み
  final NoteSearchScope scope;
  // scope == server のときの対象ホスト名（例: misskey.io）
  final String host;
  // scope == user のときの対象ユーザー（@name または @name@host 形式で入力）
  final String userAcct;
  // scope == user のとき、userAcct から解決した userId（loadMore で再利用）
  final String? resolvedUserId;

  const NoteSearchState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
    this.rangeStart,
    this.rangeEnd,
    this.scope = NoteSearchScope.all,
    this.host = '',
    this.userAcct = '',
    this.resolvedUserId,
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
    NoteSearchScope? scope,
    String? host,
    String? userAcct,
    String? resolvedUserId,
  }) => NoteSearchState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
    rangeStart: clearRange ? null : (rangeStart ?? this.rangeStart),
    rangeEnd: clearRange ? null : (rangeEnd ?? this.rangeEnd),
    scope: scope ?? this.scope,
    host: host ?? this.host,
    userAcct: userAcct ?? this.userAcct,
    resolvedUserId: resolvedUserId ?? this.resolvedUserId,
  );
}

final noteSearchProvider =
    StateNotifierProvider<NoteSearchNotifier, NoteSearchState>(
      (ref) => NoteSearchNotifier(ref),
    );

class NoteSearchNotifier extends StateNotifier<NoteSearchState> {
  final Ref _ref;
  // リクエスト世代トークン。新規検索ごとに増分し、await 完了後に値が変わって
  // いれば「別の検索に切り替わった後に遅れて返ってきた古い結果」とみなして破棄する。
  // これがないと飛行中の loadMore が新しい検索結果を上書き・混入させ、
  // 古い hasMore が居座って無限スクロールが止まる。
  int _requestId = 0;

  NoteSearchNotifier(this._ref) : super(const NoteSearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    final reqId = ++_requestId;
    // 期間フィルタ・検索対象は検索をまたいで保持する
    state = NoteSearchState(
      isLoading: true,
      query: query,
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
      scope: state.scope,
      host: state.host,
      userAcct: state.userAcct,
    );
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    // 検索対象ごとの入力バリデーションと userId 解決
    if (state.scope == NoteSearchScope.server && state.host.trim().isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: const SearchError(
          type: SearchErrorType.unknown,
          message: '対象サーバーのホスト名を入力してください',
        ),
      );
      return;
    }
    String? userId;
    if (state.scope == NoteSearchScope.user) {
      if (state.userAcct.trim().isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: const SearchError(
            type: SearchErrorType.unknown,
            message: '対象ユーザーを入力してください（例: @name@example.com）',
          ),
        );
        return;
      }
      userId = await _resolveUserId(api, state.userAcct);
      if (reqId != _requestId) return;
      if (userId == null) {
        state = state.copyWith(
          isLoading: false,
          error: const SearchError(
            type: SearchErrorType.unknown,
            message: '指定したユーザーが見つかりませんでした',
          ),
        );
        return;
      }
    }
    try {
      final notes = await api.searchNotes(
        query: query,
        rangeStartAt: _rangeStartAt(),
        rangeEndAt: _rangeEndAt(),
        host: _hostParam(),
        userId: userId,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        notes: notes,
        isLoading: false,
        hasMore: notes.length >= 20,
        clearError: true,
        resolvedUserId: userId,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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
    // 現在の検索に紐づく世代を捕捉。await 中に新規検索が走ったら結果を捨てる。
    final reqId = _requestId;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotes(
        query: state.query,
        untilId: state.notes.last.id,
        rangeStartAt: _rangeStartAt(),
        rangeEndAt: _rangeEndAt(),
        host: _hostParam(),
        userId: state.resolvedUserId,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        notes: [...state.notes, ...notes],
        isLoading: false,
        hasMore: notes.length >= 20,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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

  /// 検索対象を切り替える。入力済みクエリがあれば同条件で即再検索する。
  /// ただし server / user は対象が未入力のうちは自動再検索しない
  /// （ホスト名・ユーザー入力後に明示的な検索操作で実行する）。
  void setScope(NoteSearchScope scope) {
    if (state.scope == scope) return;
    state = state.copyWith(scope: scope);
    if (state.query.trim().isEmpty) return;
    if (scope == NoteSearchScope.server && state.host.trim().isEmpty) return;
    if (scope == NoteSearchScope.user && state.userAcct.trim().isEmpty) return;
    search(state.query);
  }

  /// scope == server のときの対象ホスト名を更新する（再検索は明示操作に委ねる）。
  void setScopeHost(String host) => state = state.copyWith(host: host);

  /// scope == user のときの対象ユーザーを更新する（再検索は明示操作に委ねる）。
  void setScopeUserAcct(String acct) => state = state.copyWith(userAcct: acct);

  /// 現在の scope から notes/search の host パラメータを算出する。
  /// all / user は null（絞り込みなし）、local は '.'、server は入力ホスト名。
  String? _hostParam() {
    switch (state.scope) {
      case NoteSearchScope.all:
      case NoteSearchScope.user:
        return null;
      case NoteSearchScope.local:
        return '.';
      case NoteSearchScope.server:
        final h = state.host.trim();
        return h.isEmpty ? null : h;
    }
  }

  /// `@name` / `@name@host` / `name@host` 形式の入力から userId を解決する。
  /// 見つからない場合は null を返す。
  Future<String?> _resolveUserId(MisskeyApi api, String acct) async {
    var s = acct.trim();
    if (s.startsWith('@')) s = s.substring(1);
    final parts = s.split('@');
    final username = parts[0];
    if (username.isEmpty) return null;
    final userHost = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    try {
      final user = await api.getUserByUsername(username, userHost: userHost);
      return user.id;
    } catch (_) {
      return null;
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
    // 検索結果はクリアするが、期間フィルタ（rangeStart/rangeEnd）と
    // 検索対象（scope/host/userAcct）は保持する。
    // 範囲の完全解除はチップの × から setDateRange(null, null) で行う。
    state = NoteSearchState(
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
      scope: state.scope,
      host: state.host,
      userAcct: state.userAcct,
    );
  }

  /// プルリフレッシュ用。現在のクエリ・条件のまま先頭から再検索する。
  Future<void> refresh() => search(state.query);
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
  // リクエスト世代トークン（[NoteSearchNotifier] と同様、古い応答の破棄用）。
  int _requestId = 0;

  TagNoteSearchNotifier(this._ref) : super(const TagNoteSearchState());

  Future<void> search(String tag) async {
    final trimmed = tag.trim().replaceAll('#', '');
    if (trimmed.isEmpty) return;
    final reqId = ++_requestId;
    state = TagNoteSearchState(isLoading: true, tag: trimmed);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotesByTag(tag: trimmed);
      if (reqId != _requestId) return;
      state = state.copyWith(
        notes: notes,
        isLoading: false,
        hasMore: notes.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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
    final reqId = _requestId;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final notes = await api.searchNotesByTag(
        tag: state.tag,
        untilId: state.notes.last.id,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        notes: [...state.notes, ...notes],
        isLoading: false,
        hasMore: notes.length >= 20,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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

  /// プルリフレッシュ用。現在のタグのまま先頭から再検索する。
  Future<void> refresh() => search(state.tag);
}

// ---- ユーザー検索（users/search）----

/// ユーザー検索の検索対象。
/// all: 全て（combined）/ local: ローカル / remote: リモート
enum UserSearchOrigin { all, local, remote }

extension UserSearchOriginApi on UserSearchOrigin {
  /// users/search の origin パラメータ値へ変換する。
  String get apiValue => switch (this) {
    UserSearchOrigin.all => 'combined',
    UserSearchOrigin.local => 'local',
    UserSearchOrigin.remote => 'remote',
  };
}

class UserSearchState {
  final List<UserModel> users;
  final bool isLoading;
  final bool hasMore;
  final SearchError? error;
  final String query;
  final UserSearchOrigin origin;

  const UserSearchState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
    this.origin = UserSearchOrigin.all,
  });

  UserSearchState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    bool? hasMore,
    SearchError? error,
    bool clearError = false,
    String? query,
    UserSearchOrigin? origin,
  }) => UserSearchState(
    users: users ?? this.users,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    query: query ?? this.query,
    origin: origin ?? this.origin,
  );
}

final userSearchProvider =
    StateNotifierProvider<UserSearchNotifier, UserSearchState>(
      (ref) => UserSearchNotifier(ref),
    );

class UserSearchNotifier extends StateNotifier<UserSearchState> {
  final Ref _ref;
  // リクエスト世代トークン（[NoteSearchNotifier] と同様、古い応答の破棄用）。
  int _requestId = 0;

  UserSearchNotifier(this._ref) : super(const UserSearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    final reqId = ++_requestId;
    // 検索対象は検索をまたいで保持する
    state = UserSearchState(
      isLoading: true,
      query: query,
      origin: state.origin,
    );
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final users = await api.searchUsers(
        query: query,
        origin: state.origin.apiValue,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        users: users,
        isLoading: false,
        hasMore: users.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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
    final reqId = _requestId;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final users = await api.searchUsers(
        query: state.query,
        offset: state.users.length,
        origin: state.origin.apiValue,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        users: [...state.users, ...users],
        isLoading: false,
        hasMore: users.length >= 20,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        error: SearchError(
          type: SearchErrorType.unknown,
          message: e.toString(),
        ),
      );
    }
  }

  /// 検索対象を切り替える。入力済みクエリがあれば同条件で即再検索する。
  void setOrigin(UserSearchOrigin origin) {
    if (state.origin == origin) return;
    state = state.copyWith(origin: origin);
    if (state.query.trim().isNotEmpty) search(state.query);
  }

  void clear() {
    // 検索対象（origin）は保持する
    state = UserSearchState(origin: state.origin);
  }

  /// プルリフレッシュ用。現在のクエリ・条件のまま先頭から再検索する。
  Future<void> refresh() => search(state.query);
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
  // リクエスト世代トークン（[NoteSearchNotifier] と同様、古い応答の破棄用）。
  int _requestId = 0;

  HashtagSearchNotifier(this._ref) : super(const HashtagSearchState());

  Future<void> search(String query) async {
    final trimmed = query.trim().replaceAll('#', '');
    if (trimmed.isEmpty) return;
    final reqId = ++_requestId;
    state = HashtagSearchState(isLoading: true, query: trimmed);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final tags = await api.searchHashtags(query: trimmed);
      if (reqId != _requestId) return;
      state = state.copyWith(
        hashtags: tags,
        isLoading: false,
        hasMore: tags.length >= 20,
        clearError: true,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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
    final reqId = _requestId;
    state = state.copyWith(isLoading: true);
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final tags = await api.searchHashtags(
        query: state.query,
        offset: state.hashtags.length,
      );
      if (reqId != _requestId) return;
      state = state.copyWith(
        hashtags: [...state.hashtags, ...tags],
        isLoading: false,
        hasMore: tags.length >= 20,
      );
    } on DioException catch (e) {
      if (reqId != _requestId) return;
      state = state.copyWith(isLoading: false, error: _parseDioError(e));
    } catch (e) {
      if (reqId != _requestId) return;
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

  /// プルリフレッシュ用。現在のクエリのまま先頭から再検索する。
  Future<void> refresh() => search(state.query);
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
