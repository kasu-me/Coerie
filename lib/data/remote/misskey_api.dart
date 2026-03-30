import 'package:dio/dio.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';

class MisskeyApi {
  final String host;
  final String? token;
  final Dio _dio;

  MisskeyApi({required this.host, this.token})
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://$host/api/',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
        ),
      );

  Map<String, dynamic> _body(Map<String, dynamic> params) {
    if (token != null) params['i'] = token;
    return params;
  }

  // ---- アカウント ----

  Future<UserModel> getMe() async {
    final res = await _dio.post('i', data: _body({}));
    return UserModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  // ---- タイムライン ----

  Future<List<NoteModel>> getTimeline({
    required String endpoint,
    int limit = 20,
    String? untilId,
    String? sinceId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (sinceId != null) params['sinceId'] = sinceId;

    final res = await _dio.post(endpoint, data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  // ---- 投稿 ----

  Future<NoteModel> createNote({
    required String text,
    String visibility = 'public',
    String? replyId,
    List<String> fileIds = const [],
  }) async {
    final params = <String, dynamic>{'text': text, 'visibility': visibility};
    if (replyId != null) params['replyId'] = replyId;
    if (fileIds.isNotEmpty) params['fileIds'] = fileIds;

    final res = await _dio.post('notes/create', data: _body(params));
    return NoteModel.fromJson(
      (res.data as Map<String, dynamic>)['createdNote'] as Map<String, dynamic>,
      host: host,
    );
  }

  // ---- リアクション ----

  Future<void> createReaction(String noteId, String reaction) async {
    await _dio.post(
      'notes/reactions/create',
      data: _body({'noteId': noteId, 'reaction': reaction}),
    );
  }

  Future<void> deleteReaction(String noteId) async {
    await _dio.post('notes/reactions/delete', data: _body({'noteId': noteId}));
  }

  // ---- リノート ----

  Future<NoteModel> renote(String noteId) async {
    final res = await _dio.post(
      'notes/create',
      data: _body({'renoteId': noteId}),
    );
    return NoteModel.fromJson(
      (res.data as Map<String, dynamic>)['createdNote'] as Map<String, dynamic>,
      host: host,
    );
  }

  // ---- ユーザー ----

  Future<UserModel> getUser(String userId) async {
    final res = await _dio.post('users/show', data: _body({'userId': userId}));
    return UserModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  Future<List<NoteModel>> getUserNotes({
    required String userId,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('users/notes', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  // ---- カスタム絵文字 ----

  Future<List<Map<String, dynamic>>> getEmojis() async {
    final res = await _dio.get('emojis');
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      data['emojis'] as List<dynamic>? ?? [],
    );
  }
}
