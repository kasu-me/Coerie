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
    Map<String, dynamic> extraParams = const {},
  }) async {
    final params = <String, dynamic>{'limit': limit, ...extraParams};
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
    String? cw,
    String visibility = 'public',
    String? replyId,
    List<String> fileIds = const [],
  }) async {
    final params = <String, dynamic>{'visibility': visibility};
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (cw != null && cw.isNotEmpty) params['cw'] = cw;
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

  Future<void> unrenote(String noteId) async {
    await _dio.post('notes/unrenote', data: _body({'noteId': noteId}));
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
    bool withFiles = false,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (withFiles) params['withFiles'] = true;
    final res = await _dio.post('users/notes', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  Future<List<NoteModel>> getUserPinnedNotes(String userId) async {
    final user = await getUser(userId);
    if (user.pinnedNoteIds.isEmpty) return [];
    final futures = user.pinnedNoteIds.map((id) async {
      final res = await _dio.post('notes/show', data: _body({'noteId': id}));
      return NoteModel.fromJson(res.data as Map<String, dynamic>, host: host);
    });
    return Future.wait(futures);
  }

  Future<List<UserModel>> getFollowing(
    String userId, {
    int limit = 30,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('users/following', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      return UserModel.fromJson(
        map['followee'] as Map<String, dynamic>,
        host: host,
      );
    }).toList();
  }

  Future<List<UserModel>> getFollowers(
    String userId, {
    int limit = 30,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('users/followers', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      return UserModel.fromJson(
        map['follower'] as Map<String, dynamic>,
        host: host,
      );
    }).toList();
  }

  Future<void> followUser(String userId) async {
    await _dio.post('following/create', data: _body({'userId': userId}));
  }

  Future<void> unfollowUser(String userId) async {
    await _dio.post('following/delete', data: _body({'userId': userId}));
  }

  // ---- ドライブ ----

  /// ドライブのフォルダ一覧を取得する。
  Future<List<Map<String, dynamic>>> getDriveFolders({String? folderId}) async {
    final params = <String, dynamic>{};
    if (folderId != null) params['folderId'] = folderId;
    final res = await _dio.post('drive/folders', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// ドライブのファイル一覧を取得する。
  Future<List<DriveFileModel>> getDriveFiles({
    int limit = 40,
    String? untilId,
    String? type,
    String? folderId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (type != null) params['type'] = type;
    if (folderId != null) params['folderId'] = folderId;
    final res = await _dio.post('drive/files', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((f) => DriveFileModel.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// ドライブファイルを削除する。
  Future<void> deleteFile(String fileId) async {
    await _dio.post('drive/files/delete', data: _body({'fileId': fileId}));
  }

  /// ドライブファイルを指定フォルダに移動する（nullでルートに移動）。
  Future<void> moveFile(String fileId, {String? folderId}) async {
    final params = <String, dynamic>{'fileId': fileId, 'folderId': folderId};
    await _dio.post('drive/files/update', data: _body(params));
  }

  /// ファイルをDriveにアップロードし、ファイルIDを返す。
  Future<String> uploadFile(
    File file, {
    String? name,
    bool isSensitive = false,
  }) async {
    final fileName = name ?? file.path.split('/').last.split('\\').last;
    final formData = FormData.fromMap({
      'i': token,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (name != null) 'name': name,
      if (isSensitive) 'isSensitive': 'true',
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

  // ---- リスト ----

  Future<List<Map<String, dynamic>>> getLists() async {
    final res = await _dio.post('users/lists/list', data: _body({}));
    return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ---- アンテナ ----

  Future<List<Map<String, dynamic>>> getAntennas() async {
    final res = await _dio.post('antennas/list', data: _body({}));
    return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ---- ノート操作 ----

  Future<NoteModel> getNote(String noteId) async {
    final res = await _dio.post('notes/show', data: _body({'noteId': noteId}));
    return NoteModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  Future<void> deleteNote(String noteId) async {
    await _dio.post('notes/delete', data: _body({'noteId': noteId}));
  }

  Future<List<NoteModel>> getNoteReplies(
    String noteId, {
    int limit = 50,
  }) async {
    final res = await _dio.post(
      'notes/replies',
      data: _body({'noteId': noteId, 'limit': limit}),
    );
    return (res.data as List<dynamic>)
        .map((e) => NoteModel.fromJson(e as Map<String, dynamic>, host: host))
        .toList();
  }

  // ---- ミュート（ユーザー） ----

  Future<List<Map<String, dynamic>>> getMutingList({
    int limit = 100,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('mute/list', data: _body(params));
    return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> muteUser(String userId) async {
    await _dio.post('mute/create', data: _body({'userId': userId}));
  }

  Future<void> unmuteUser(String userId) async {
    await _dio.post('mute/delete', data: _body({'userId': userId}));
  }

  // ---- ブロック（ユーザー） ----

  Future<List<Map<String, dynamic>>> getBlockingList({
    int limit = 100,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('blocking/list', data: _body(params));
    return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> blockUser(String userId) async {
    await _dio.post('blocking/create', data: _body({'userId': userId}));
  }

  Future<void> unblockUser(String userId) async {
    await _dio.post('blocking/delete', data: _body({'userId': userId}));
  }

  // ---- ワードミュート ----

  /// 現在のワードミュート設定を取得する（i エンドポイントから）
  Future<List<List<String>>> getMutedWords() async {
    final res = await _dio.post('i', data: _body({}));
    final data = res.data as Map<String, dynamic>;
    final raw = data['mutedWords'] as List<dynamic>? ?? [];
    return raw
        .map((item) {
          if (item is List) return item.cast<String>();
          if (item is String) return [item];
          return <String>[];
        })
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// プロフィールを更新する
  Future<void> updateProfile({String? name, String? description}) async {
    final params = <String, dynamic>{};
    if (name != null) params['name'] = name;
    if (description != null) params['description'] = description;
    await _dio.post('i/update', data: _body(params));
  }

  /// ワードミュートを更新する
  Future<void> setMutedWords(List<List<String>> words) async {
    await _dio.post('i/update', data: _body({'mutedWords': words}));
  }
}
