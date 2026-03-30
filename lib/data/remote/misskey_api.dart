import 'dart:io';
import 'package:dio/dio.dart';
import '../../data/models/note_model.dart';
import '../../data/models/notification_model.dart';
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
    String? text,
    String visibility = 'public',
    String? replyId,
    List<String> fileIds = const [],
  }) async {
    final params = <String, dynamic>{'visibility': visibility};
    if (text != null && text.isNotEmpty) params['text'] = text;
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

  // ---- ドライブ ----

  /// ドライブのファイル一覧を取得する。
  Future<List<DriveFileModel>> getDriveFiles({
    int limit = 40,
    String? untilId,
    String? type,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (type != null) params['type'] = type;
    final res = await _dio.post('drive/files', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((f) => DriveFileModel.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// ファイルをDriveにアップロードし、ファイルIDを返す。
  Future<String> uploadFile(File file, {String? name}) async {
    final fileName = name ?? file.path.split('/').last.split('\\').last;
    final formData = FormData.fromMap({
      'i': token,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (name != null) 'name': name,
    });

    // Drive upload は multipart/form-data を使用
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://$host/api/',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final res = await dio.post('drive/files/create', data: formData);
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  // ---- カスタム絵文字 ----

  Future<List<Map<String, dynamic>>> getEmojis() async {
    final res = await _dio.get('emojis');
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      data['emojis'] as List<dynamic>? ?? [],
    );
  }

  // ---- 通知 ----

  Future<List<NotificationModel>> getNotifications({
    int limit = 20,
    String? untilId,
    String? sinceId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (sinceId != null) params['sinceId'] = sinceId;
    final res = await _dio.post('i/notifications', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map(
          (n) =>
              NotificationModel.fromJson(n as Map<String, dynamic>, host: host),
        )
        .toList();
  }

  Future<void> markNotificationsRead() async {
    await _dio.post('notifications/mark-all-as-read', data: _body({}));
  }
}
