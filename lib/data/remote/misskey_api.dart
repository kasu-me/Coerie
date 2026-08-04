import 'dart:io';
import 'package:dio/dio.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/chat_room_model.dart';
import '../../data/models/clip_model.dart';
import '../../data/models/gallery_post_model.dart';
import '../../data/models/antenna_model.dart';
import '../../data/models/channel_model.dart';
import '../../data/models/custom_emoji_model.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/drive_folder_model.dart';
import '../../data/models/note_model.dart';
import '../../data/models/note_state_model.dart';
import '../../data/models/page_model.dart';
import '../../data/models/notification_model.dart';
import '../../data/models/user_list_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/announcement_model.dart';

class MisskeyApi {
  final String host;
  final String? token;
  final Dio _dio;

  /// キャッシュされたサーバーの最大ファイルサイズ（バイト）
  int? _maxFileSize;

  /// キャッシュされたノート検索（notes/search）の利用可否
  bool? _canSearchNotes;

  /// `i` 応答の `policies`（ロールポリシー）。複数の設定値が同じ応答から
  /// 得られるため、インスタンスごとに1回だけ取得して使い回す。
  /// 未認証時・取得失敗時は null を返し、各呼び出し元のフォールバックに委ねる。
  Future<Map<String, dynamic>?>? _policiesFuture;

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

  /// `i` 応答の `policies` を取得する。取得済みの Future を使い回すため、
  /// 複数の設定値を参照しても `i` へのリクエストは1回で済む。
  Future<Map<String, dynamic>?> _fetchPolicies() {
    if (token == null) return Future.value(null);
    return _policiesFuture ??= () async {
      try {
        final res = await _dio.post('i', data: _body({}));
        final data = res.data as Map<String, dynamic>;
        return data['policies'] as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }();
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
    String? renoteId,
    List<String> fileIds = const [],
    List<String>? visibleUserIds,
    Map<String, dynamic>? poll,
    String? channelId,
  }) async {
    final params = <String, dynamic>{'visibility': visibility};
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (cw != null && cw.isNotEmpty) params['cw'] = cw;
    if (replyId != null) params['replyId'] = replyId;
    if (renoteId != null) params['renoteId'] = renoteId;
    if (fileIds.isNotEmpty) params['fileIds'] = fileIds;
    if (visibleUserIds != null && visibleUserIds.isNotEmpty) {
      params['visibleUserIds'] = visibleUserIds;
    }
    if (poll != null) {
      params['poll'] = poll;
    }
    if (channelId != null) {
      params['channelId'] = channelId;
    }

    final res = await _dio.post('notes/create', data: _body(params));
    return NoteModel.fromJson(
      (res.data as Map<String, dynamic>)['createdNote'] as Map<String, dynamic>,
      host: host,
    );
  }

  // ---- 投票 ----

  Future<void> votePoll(String noteId, int choice) async {
    await _dio.post(
      'notes/polls/vote',
      data: _body({'noteId': noteId, 'choice': choice}),
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

  /// 指定ノートのリアクションを付けたユーザー一覧を取得する。
  /// API の戻り値が複数形式になり得るため、含まれるユーザーオブジェクトを優先的にパースし、
  /// userId のみが返る場合は `users/show` で補完する。
  Future<List<UserModel>> getNoteReactions(
    String noteId, {
    String? reaction,
    int limit = 100,
  }) async {
    final params = <String, dynamic>{'noteId': noteId, 'limit': limit};
    if (reaction != null) params['type'] = reaction;
    final res = await _dio.post('notes/reactions', data: _body(params));
    final data = res.data;

    final List<UserModel> users = [];
    final Set<String> idsToFetch = {};

    void collectFromEntry(dynamic entry) {
      if (entry is Map<String, dynamic>) {
        if (entry.containsKey('user') && entry['user'] is Map) {
          users.add(
            UserModel.fromJson(
              entry['user'] as Map<String, dynamic>,
              host: host,
            ),
          );
        } else if (entry.containsKey('userId') && entry['userId'] is String) {
          idsToFetch.add(entry['userId'] as String);
        } else if (entry.containsKey('user') && entry['user'] is String) {
          idsToFetch.add(entry['user'] as String);
        } else if (entry.containsKey('id')) {
          // そのままユーザーオブジェクトが来ている場合
          users.add(UserModel.fromJson(entry, host: host));
        }
      }
    }

    if (data is List) {
      for (final e in data) {
        collectFromEntry(e);
      }
    } else if (data is Map<String, dynamic>) {
      // keys may be reaction strings mapping to lists
      for (final entry in data.entries) {
        // reaction フィルタが指定されていれば、一致するキーのみを処理する
        if (reaction != null && entry.key != reaction) continue;
        final v = entry.value;
        if (v is List) {
          for (final e in v) {
            collectFromEntry(e);
          }
        } else {
          collectFromEntry(v);
        }
      }
    }

    if (idsToFetch.isNotEmpty) {
      final futures = idsToFetch.map((id) => getUser(id));
      final fetched = await Future.wait(futures);
      users.addAll(fetched);
    }

    return users;
  }

  // ---- リノート ----

  Future<NoteModel> renote(
    String noteId, {
    String visibility = 'public',
  }) async {
    final res = await _dio.post(
      'notes/create',
      data: _body({'renoteId': noteId, 'visibility': visibility}),
    );
    return NoteModel.fromJson(
      (res.data as Map<String, dynamic>)['createdNote'] as Map<String, dynamic>,
      host: host,
    );
  }

  Future<void> unrenote(String noteId) async {
    await _dio.post('notes/unrenote', data: _body({'noteId': noteId}));
  }

  /// 指定ノートをリノートしたユーザー一覧を取得する（notes/renotes）。
  Future<List<UserModel>> getNoteRenotes(
    String noteId, {
    int limit = 100,
  }) async {
    final params = <String, dynamic>{'noteId': noteId, 'limit': limit};
    final res = await _dio.post('notes/renotes', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.map((n) {
      final map = n as Map<String, dynamic>;
      return UserModel.fromJson(
        map['user'] as Map<String, dynamic>,
        host: host,
      );
    }).toList();
  }

  // ---- ユーザー ----

  Future<UserModel> getUser(String userId) async {
    final res = await _dio.post('users/show', data: _body({'userId': userId}));
    return UserModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  Future<UserModel> getUserByUsername(
    String username, {
    String? userHost,
  }) async {
    final params = <String, dynamic>{'username': username};
    if (userHost != null) params['host'] = userHost;
    final res = await _dio.post('users/show', data: _body(params));
    return UserModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  Future<List<NoteModel>> getUserNotes({
    required String userId,
    int limit = 20,
    String? untilId,
    bool withFiles = false,
    bool withReplies = false,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (withFiles) params['withFiles'] = true;
    // withReplies を有効にすると他ユーザーへのリプライも含まれる
    if (withReplies) params['withReplies'] = true;
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

  /// 指定ユーザー群に対するリレーションを一括取得する。
  ///
  /// 返却は userId -> relation map の形。
  /// Misskey の `users/relation` エンドポイントの必須パラメータは `userId` で、
  /// 単一の文字列または文字列配列を受け付けます。
  /// 応答は relation オブジェクトの配列（各要素は取得対象ユーザーIDを `id` キーに持つ）で、
  /// 単一IDを渡した場合は単一オブジェクトが返ります。
  /// サーバ実装やバージョンで形式が異なることがあるため、Map / List の両ケースを扱います。
  Future<Map<String, Map<String, dynamic>>> getUsersRelation(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    final params = <String, dynamic>{'userId': userIds};
    final res = await _dio.post('users/relation', data: _body(params));
    final data = res.data;

    final Map<String, Map<String, dynamic>> result = {};
    if (data is Map<String, dynamic>) {
      // 既に userId -> relation のマップになっている可能性
      for (final entry in data.entries) {
        if (entry.value is Map<String, dynamic>) {
          result[entry.key] = Map<String, dynamic>.from(
            entry.value as Map<String, dynamic>,
          );
        } else {
          result[entry.key] = {'value': entry.value};
        }
      }
    } else if (data is List) {
      for (final e in data) {
        if (e is Map<String, dynamic>) {
          // relation オブジェクトに userId / id / target などが含まれる場合がある
          final id =
              e['userId'] as String? ??
              e['id'] as String? ??
              e['target'] as String?;
          if (id != null) {
            result[id] = Map<String, dynamic>.from(e);
          }
        }
      }
    }
    return result;
  }

  Future<void> followUser(String userId) async {
    await _dio.post('following/create', data: _body({'userId': userId}));
  }

  Future<void> unfollowUser(String userId) async {
    await _dio.post('following/delete', data: _body({'userId': userId}));
  }

  /// フォロワーを解除する（following/invalidate）
  Future<void> invalidateFollower(String userId) async {
    await _dio.post('following/invalidate', data: _body({'userId': userId}));
  }

  /// フォローリクエスト一覧を取得する（following/requests/list）
  Future<List<UserModel>> getFollowRequests() async {
    final res = await _dio.post('following/requests/list', data: _body({}));
    final data = res.data;

    final List<UserModel> users = [];
    final Set<String> idsToFetch = {};

    void collect(dynamic entry) {
      if (entry is Map<String, dynamic>) {
        if (entry.containsKey('user') && entry['user'] is Map) {
          users.add(
            UserModel.fromJson(
              entry['user'] as Map<String, dynamic>,
              host: host,
            ),
          );
        } else if (entry.containsKey('follower') && entry['follower'] is Map) {
          users.add(
            UserModel.fromJson(
              entry['follower'] as Map<String, dynamic>,
              host: host,
            ),
          );
        } else if (entry.containsKey('userId') && entry['userId'] is String) {
          idsToFetch.add(entry['userId'] as String);
        } else if (entry.containsKey('id') && entry['id'] is String) {
          // may be a user object itself
          users.add(UserModel.fromJson(entry, host: host));
        }
      } else if (entry is String) {
        idsToFetch.add(entry);
      }
    }

    if (data is List) {
      for (final e in data) {
        collect(e);
      }
    } else if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is List) {
          for (final e in v) {
            collect(e);
          }
        } else {
          collect(v);
        }
      }
    }

    if (idsToFetch.isNotEmpty) {
      final futures = idsToFetch.map((id) => getUser(id));
      final fetched = await Future.wait(futures);
      users.addAll(fetched);
    }

    return users;
  }

  /// フォローリクエストを許可する（following/requests/accept）
  Future<void> acceptFollowRequest(String userId) async {
    await _dio.post(
      'following/requests/accept',
      data: _body({'userId': userId}),
    );
  }

  /// フォローリクエストを拒否する（following/requests/reject）
  Future<void> rejectFollowRequest(String userId) async {
    await _dio.post(
      'following/requests/reject',
      data: _body({'userId': userId}),
    );
  }

  // ---- ドライブ ----

  /// ドライブの使用状況（容量・使用量、単位バイト）を取得する。
  Future<({int capacity, int usage})> getDriveInfo() async {
    final res = await _dio.post('drive', data: _body({}));
    final data = res.data as Map<String, dynamic>;
    return (
      capacity: (data['capacity'] as num).toInt(),
      usage: (data['usage'] as num).toInt(),
    );
  }

  /// ドライブのフォルダ一覧を取得する。
  Future<List<DriveFolderModel>> getDriveFolders({String? folderId}) async {
    final params = <String, dynamic>{};
    if (folderId != null) params['folderId'] = folderId;
    final res = await _dio.post('drive/folders', data: _body(params));
    return (res.data as List<dynamic>)
        .map((e) => DriveFolderModel.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// ドライブファイルのセンシティブ設定を更新する。
  Future<void> updateFileSensitive(
    String fileId, {
    required bool isSensitive,
  }) async {
    await _dio.post(
      'drive/files/update',
      data: _body({'fileId': fileId, 'isSensitive': isSensitive}),
    );
  }

  /// ドライブフォルダを指定フォルダに移動する（nullでルートに移動）。
  Future<void> moveFolder(String folderId, {String? parentId}) async {
    final params = <String, dynamic>{
      'folderId': folderId,
      'parentId': parentId,
    };
    await _dio.post('drive/folders/update', data: _body(params));
  }

  /// ドライブのフォルダを作成する。parent は null でルート。
  Future<DriveFolderModel> createDriveFolder({
    required String name,
    String? parentId,
  }) async {
    final params = <String, dynamic>{'name': name};
    if (parentId != null) params['parentId'] = parentId;
    final res = await _dio.post('drive/folders/create', data: _body(params));
    return DriveFolderModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// ドライブのフォルダ情報を更新する（名前変更など）。
  Future<void> updateDriveFolder(String folderId, {String? name}) async {
    final params = <String, dynamic>{'folderId': folderId};
    if (name != null) params['name'] = name;
    await _dio.post('drive/folders/update', data: _body(params));
  }

  /// ドライブフォルダを削除する。
  Future<void> deleteDriveFolder(String folderId) async {
    await _dio.post(
      'drive/folders/delete',
      data: _body({'folderId': folderId}),
    );
  }

  /// 実効的な最大ファイルサイズ（バイト）を取得する。
  ///
  /// 現行Misskeyの実効上限はロールポリシーで決まり、`i` エンドポイント応答の
  /// `policies.maxFileSizeMb`（MB単位、デフォルト30）が正の値です。
  /// サーバー側で min(サーバー設定, ロール値) に集約済みの値が返ります。
  /// 認証がない・旧サーバー・取得失敗時は `meta` の `maxFileSize` にフォールバックし、
  /// それも取れない場合はロールポリシーのデフォルト値（30MB）を返す。
  Future<int> fetchMaxFileSize() async {
    if (_maxFileSize != null) return _maxFileSize!;
    const fallback = 30 * 1024 * 1024;
    // 認証済みならロールポリシーの実効上限を優先して取得する。
    // 未認証・取得失敗（トークン失効・レートリミット等）や値なしの場合は
    // 後続の meta フォールバックに落ちる。
    final mb = ((await _fetchPolicies())?['maxFileSizeMb'] as num?)?.toInt();
    if (mb != null) {
      _maxFileSize = mb * 1024 * 1024;
      return _maxFileSize!;
    }
    try {
      // 旧サーバー・未認証・値なしの場合は meta のサーバー設定値にフォールバック。
      final res = await _dio.post('meta', data: {'detail': false});
      final data = res.data as Map<String, dynamic>;
      _maxFileSize = (data['maxFileSize'] as num?)?.toInt() ?? fallback;
    } catch (_) {
      _maxFileSize = fallback;
    }
    return _maxFileSize!;
  }

  /// ノート検索（notes/search）がこのサーバーで利用可能かを取得する。
  /// Misskey v13 以降は `i` 応答の `policies.canSearchNotes` で判定できる。
  /// 取得失敗・キー欠落（旧サーバー等）の場合は true を返し、
  /// 実行時の事後エラー処理（search_provider 側）にフォールバックする。
  Future<bool> fetchCanSearchNotes() async {
    if (_canSearchNotes != null) return _canSearchNotes!;
    if (token == null) return true;
    // 未認証・取得失敗・キー欠落の場合は、実行時の事後エラー処理に
    // フォールバックするため true とする。
    _canSearchNotes =
        (await _fetchPolicies())?['canSearchNotes'] as bool? ?? true;
    return _canSearchNotes!;
  }

  /// ファイルをDriveにアップロードし、ファイルIDを返す。
  Future<String> uploadFile(
    File file, {
    String? name,
    bool isSensitive = false,
    String? folderId,
  }) async {
    // アップロード前にサーバーのファイルサイズ制限を確認
    final maxSize = await fetchMaxFileSize();
    final fileSize = await file.length();
    if (fileSize > maxSize) {
      final maxMB = maxSize ~/ (1024 * 1024);
      final fileMB = fileSize ~/ (1024 * 1024);
      throw Exception(
        'ファイルサイズが大きすぎます（${fileMB}MB）。'
        'このサーバーの上限は${maxMB}MBです。'
        '動画を短くするか、画質を下げてお試しください。',
      );
    }

    final fileName = name ?? file.path.split('/').last.split('\\').last;
    final formData = FormData.fromMap({
      'i': token,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      'name': ?name,
      if (isSensitive) 'isSensitive': 'true',
      'folderId': ?folderId,
    });

    // Drive upload は multipart/form-data を使用
    // 大きなファイルのアップロードに対応するためタイムアウトを長めに設定
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://$host/api/',
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    try {
      final res = await dio.post('drive/files/create', data: formData);
      return (res.data as Map<String, dynamic>)['id'] as String;
    } on DioException catch (e) {
      if (e.response?.statusCode == 413) {
        final maxMB = maxSize ~/ (1024 * 1024);
        throw Exception(
          'ファイルサイズが大きすぎます。'
          'このサーバーの上限は${maxMB}MBです。'
          '動画を短くするか、画質を下げてお試しください。',
        );
      }
      rethrow;
    }
  }

  // ---- カスタム絵文字 ----

  Future<List<CustomEmojiModel>> getEmojis() async {
    final res = await _dio.post('emojis', data: _body({}));
    final data = res.data as Map<String, dynamic>;
    return (data['emojis'] as List<dynamic>? ?? [])
        .map((e) => CustomEmojiModel.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// サーバお知らせ一覧を取得する。
  /// Misskey API: `announcements`
  Future<List<AnnouncementModel>> getAnnouncements({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('announcements', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((e) => AnnouncementModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// お知らせを既読にする（i/read-announcement）。
  Future<void> readAnnouncement(String announcementId) async {
    // Some Misskey server implementations may expect either 'id' or 'announcementId'.
    // Send both keys to increase compatibility.
    final params = {'id': announcementId, 'announcementId': announcementId};
    await _dio.post('i/read-announcement', data: _body(params));
  }

  // ---- リスト ----

  Future<List<UserListModel>> getLists() async {
    final res = await _dio.post('users/lists/list', data: _body({}));
    return (res.data as List<dynamic>)
        .map((e) => UserListModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserListModel> createList({required String name}) async {
    final res = await _dio.post(
      'users/lists/create',
      data: _body({'name': name}),
    );
    return UserListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserListModel> updateList({
    required String listId,
    String? name,
    bool? isPublic,
  }) async {
    final params = <String, dynamic>{'listId': listId};
    if (name != null) params['name'] = name;
    if (isPublic != null) params['isPublic'] = isPublic;
    final res = await _dio.post('users/lists/update', data: _body(params));
    return UserListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteList({required String listId}) async {
    await _dio.post('users/lists/delete', data: _body({'listId': listId}));
  }

  Future<List<UserListMembershipModel>> getListMembers({
    required String listId,
    int limit = 100,
  }) async {
    final res = await _dio.post(
      'users/lists/get-memberships',
      data: _body({'listId': listId, 'forPublic': false, 'limit': limit}),
    );
    return (res.data as List<dynamic>)
        .map((e) => UserListMembershipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addListMember({
    required String listId,
    required String userId,
  }) async {
    await _dio.post(
      'users/lists/push',
      data: _body({'listId': listId, 'userId': userId}),
    );
  }

  Future<void> removeListMember({
    required String listId,
    required String userId,
  }) async {
    await _dio.post(
      'users/lists/pull',
      data: _body({'listId': listId, 'userId': userId}),
    );
  }

  // ---- アンテナ ----

  Future<List<AntennaModel>> getAntennas() async {
    final res = await _dio.post('antennas/list', data: _body({}));
    return (res.data as List<dynamic>)
        .map((e) => AntennaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AntennaModel> createAntenna({
    required String name,
    required String src,
    required List<List<String>> keywords,
    required List<List<String>> excludeKeywords,
    required List<String> users,
    required bool caseSensitive,
    required bool withReplies,
    required bool withFile,
    bool localOnly = false,
    bool excludeBots = false,
    bool excludeNotesInSensitiveChannel = false,
    String? userListId,
  }) async {
    final params = <String, dynamic>{
      'name': name,
      'src': src,
      'keywords': keywords,
      'excludeKeywords': excludeKeywords,
      'users': users,
      'caseSensitive': caseSensitive,
      'withReplies': withReplies,
      'withFile': withFile,
      'localOnly': localOnly,
      'excludeBots': excludeBots,
      'excludeNotesInSensitiveChannel': excludeNotesInSensitiveChannel,
    };
    if (userListId != null) params['userListId'] = userListId;
    final res = await _dio.post('antennas/create', data: _body(params));
    return AntennaModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AntennaModel> updateAntenna({
    required String antennaId,
    required String name,
    required String src,
    required List<List<String>> keywords,
    required List<List<String>> excludeKeywords,
    required List<String> users,
    required bool caseSensitive,
    required bool withReplies,
    required bool withFile,
    bool localOnly = false,
    bool excludeBots = false,
    bool excludeNotesInSensitiveChannel = false,
    String? userListId,
  }) async {
    final params = <String, dynamic>{
      'antennaId': antennaId,
      'name': name,
      'src': src,
      'keywords': keywords,
      'excludeKeywords': excludeKeywords,
      'users': users,
      'caseSensitive': caseSensitive,
      'withReplies': withReplies,
      'withFile': withFile,
      'localOnly': localOnly,
      'excludeBots': excludeBots,
      'excludeNotesInSensitiveChannel': excludeNotesInSensitiveChannel,
    };
    if (userListId != null) params['userListId'] = userListId;
    final res = await _dio.post('antennas/update', data: _body(params));
    return AntennaModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteAntenna({required String antennaId}) async {
    await _dio.post('antennas/delete', data: _body({'antennaId': antennaId}));
  }

  // ---- ノート操作 ----

  Future<NoteModel> getNote(String noteId) async {
    final res = await _dio.post('notes/show', data: _body({'noteId': noteId}));
    return NoteModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  Future<void> deleteNote(String noteId) async {
    await _dio.post('notes/delete', data: _body({'noteId': noteId}));
  }

  /// ノートをピン留めする（i/pin）
  Future<void> pinNote(String noteId) async {
    await _dio.post('i/pin', data: _body({'noteId': noteId}));
  }

  /// ノートのピンを解除する（i/unpin）
  Future<void> unpinNote(String noteId) async {
    await _dio.post('i/unpin', data: _body({'noteId': noteId}));
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

  /// `[{ ..., <key>: User }]` 形式のレスポンスから対象ユーザーだけを取り出す。
  /// 対象が欠けている要素は捨てる。
  List<UserModel> _unwrapUsers(dynamic data, String key) => (data as List<dynamic>)
      .map((e) => (e as Map<String, dynamic>)[key] as Map<String, dynamic>?)
      .whereType<Map<String, dynamic>>()
      .map(UserModel.fromJson)
      .toList();

  /// ミュート中のユーザー一覧（mute/list）。
  ///
  /// API は `{ id, muteeId, mutee }` の配列を返すが、画面が使うのは
  /// 対象ユーザーだけなので `mutee` を取り出して返す。
  Future<List<UserModel>> getMutingList({
    int limit = 100,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('mute/list', data: _body(params));
    return _unwrapUsers(res.data, 'mutee');
  }

  Future<void> muteUser(String userId) async {
    await _dio.post('mute/create', data: _body({'userId': userId}));
  }

  Future<void> unmuteUser(String userId) async {
    await _dio.post('mute/delete', data: _body({'userId': userId}));
  }

  // ---- ブロック（ユーザー） ----

  /// ブロック中のユーザー一覧（blocking/list）。[getMutingList] と同じ構造。
  Future<List<UserModel>> getBlockingList({
    int limit = 100,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('blocking/list', data: _body(params));
    return _unwrapUsers(res.data, 'blockee');
  }

  Future<void> blockUser(String userId) async {
    await _dio.post('blocking/create', data: _body({'userId': userId}));
  }

  Future<void> unblockUser(String userId) async {
    await _dio.post('blocking/delete', data: _body({'userId': userId}));
  }

  // ---- 通報 ----

  /// ユーザーを通報する（users/report-abuse）
  Future<void> reportAbuse(String userId, String comment) async {
    await _dio.post(
      'users/report-abuse',
      data: _body({'userId': userId, 'comment': comment}),
    );
  }

  // ---- 検索 ----

  /// notes/search: ノートをキーワード検索する
  ///
  /// [rangeStartAt] / [rangeEndAt] はエポックミリ秒で投稿日時の範囲を指定
  /// （Misskey 2026.6.0+、旧サーバーでは無視される）。
  ///
  /// [host] は検索対象サーバーを絞り込む。ローカルのみに絞る場合は `'.'` を指定する
  /// （null なら全サーバー対象）。[userId] を指定するとそのユーザーの投稿に絞り込む。
  Future<List<NoteModel>> searchNotes({
    required String query,
    int limit = 20,
    String? untilId,
    int? rangeStartAt,
    int? rangeEndAt,
    String? host,
    String? userId,
  }) async {
    final params = <String, dynamic>{'query': query, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (rangeStartAt != null) params['rangeStartAt'] = rangeStartAt;
    if (rangeEndAt != null) params['rangeEndAt'] = rangeEndAt;
    if (host != null) params['host'] = host;
    if (userId != null) params['userId'] = userId;
    final res = await _dio.post('notes/search', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map(
          (n) => NoteModel.fromJson(n as Map<String, dynamic>, host: this.host),
        )
        .toList();
  }

  /// 指定された Drive ファイルが添付されたノート一覧を取得する。
  /// Misskey サーバの検索でファイルIDをクエリに含めて検索する実装を試みます。
  Future<List<NoteModel>> getNotesByFile({
    required String fileId,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'fileId': fileId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post(
      'drive/files/attached-notes',
      data: _body(params),
    );
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  /// notes/search-by-tag: タグでノートを検索する
  Future<List<NoteModel>> searchNotesByTag({
    required String tag,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'tag': tag, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('notes/search-by-tag', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  /// users/search: ユーザーをキーワード検索する
  ///
  /// [origin] は検索対象を絞り込む。'combined'（全て・既定）/ 'local'（ローカル）/
  /// 'remote'（リモート）のいずれかを指定する。
  Future<List<UserModel>> searchUsers({
    required String query,
    int limit = 20,
    int? offset,
    String origin = 'combined',
  }) async {
    final params = <String, dynamic>{
      'query': query,
      'limit': limit,
      'detail': true,
      'origin': origin,
    };
    if (offset != null) params['offset'] = offset;
    final res = await _dio.post('users/search', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>, host: host))
        .toList();
  }

  /// hashtags/search: ハッシュタグを検索する
  Future<List<String>> searchHashtags({
    required String query,
    int limit = 20,
    int? offset,
  }) async {
    final params = <String, dynamic>{'query': query, 'limit': limit};
    if (offset != null) params['offset'] = offset;
    final res = await _dio.post('hashtags/search', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.cast<String>();
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
  Future<void> updateProfile({
    String? name,
    String? description,
    List<Map<String, dynamic>>? fields,
  }) async {
    final params = <String, dynamic>{};
    if (name != null) params['name'] = name;
    if (description != null) params['description'] = description;
    if (fields != null) params['fields'] = fields;
    await _dio.post('i/update', data: _body(params));
  }

  /// ワードミュートを更新する
  Future<void> setMutedWords(List<List<String>> words) async {
    await _dio.post('i/update', data: _body({'mutedWords': words}));
  }

  // ---- クリップ ----

  /// クリップ一覧を取得する（clips/list）
  /// userId を指定するとそのユーザーが作成したクリップを取得します。
  ///
  /// `clips/list` は 2025.8.0 からページネーション対応となり `limit` のデフォルトが
  /// 10 のため、`limit`（最大100）を明示的に指定します。`untilId` を渡すと
  /// そのIDより古いクリップを取得します。
  Future<List<ClipModel>> getClips({
    String? userId,
    int limit = 100,
    String? untilId,
  }) async {
    final cappedLimit = limit > 100 ? 100 : limit;
    final String endpoint;
    final Map<String, dynamic> params;
    if (userId != null) {
      // 他ユーザーの公開クリップは users/clips エンドポイントを使用する
      endpoint = 'users/clips';
      params = {'userId': userId, 'limit': cappedLimit};
    } else {
      // 自分のクリップは clips/list エンドポイントを使用する
      endpoint = 'clips/list';
      params = {'limit': cappedLimit};
    }
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post(endpoint, data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// クリップを取得する（clips/show）
  Future<ClipModel> getClip(String clipId) async {
    final res = await _dio.post('clips/show', data: _body({'clipId': clipId}));
    return ClipModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// クリップを作成する（clips/create）
  Future<ClipModel> createClip({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    final params = <String, dynamic>{'name': name, 'isPublic': isPublic};
    if (description != null && description.isNotEmpty) {
      params['description'] = description;
    }
    final res = await _dio.post('clips/create', data: _body(params));
    return ClipModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// クリップを削除する（clips/delete）
  Future<void> deleteClip(String clipId) async {
    await _dio.post('clips/delete', data: _body({'clipId': clipId}));
  }

  /// クリップの情報を更新する（clips/update）
  Future<ClipModel> updateClip({
    required String clipId,
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    final params = <String, dynamic>{
      'clipId': clipId,
      'name': name,
      'isPublic': isPublic,
      'description': description,
    };
    final res = await _dio.post('clips/update', data: _body(params));
    return ClipModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// クリップに含まれるノートを取得する（clips/notes）
  Future<List<NoteModel>> getClipNotes({
    required String clipId,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'clipId': clipId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('clips/notes', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((n) => NoteModel.fromJson(n as Map<String, dynamic>, host: host))
        .toList();
  }

  /// ノートをクリップに追加する（clips/add-note）
  Future<void> addNoteToClip({
    required String clipId,
    required String noteId,
  }) async {
    await _dio.post(
      'clips/add-note',
      data: _body({'clipId': clipId, 'noteId': noteId}),
    );
  }

  /// ノートをクリップから削除する（clips/remove-note）
  Future<void> removeNoteFromClip({
    required String clipId,
    required String noteId,
  }) async {
    await _dio.post(
      'clips/remove-note',
      data: _body({'clipId': clipId, 'noteId': noteId}),
    );
  }

  /// お気に入りに登録したクリップ一覧を取得する（clips/my-favorites）
  /// このエンドポイントはページネーションに対応していないため全件返る。
  Future<List<ClipModel>> getMyFavoriteClips() async {
    final res = await _dio.post('clips/my-favorites', data: _body({}));
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// クリップをお気に入りに登録する（clips/favorite）
  Future<void> favoriteClip(String clipId) async {
    await _dio.post('clips/favorite', data: _body({'clipId': clipId}));
  }

  /// クリップのお気に入りを解除する（clips/unfavorite）
  Future<void> unfavoriteClip(String clipId) async {
    await _dio.post('clips/unfavorite', data: _body({'clipId': clipId}));
  }

  // ---- チャンネル ----

  List<ChannelModel> _toChannels(dynamic data) => (data as List<dynamic>)
      .map((e) => ChannelModel.fromJson(e as Map<String, dynamic>))
      .toList();

  /// チャンネルの詳細情報を取得する（channels/show）
  Future<ChannelModel> getChannel(String channelId) async {
    final res = await _dio.post(
      'channels/show',
      data: _body({'channelId': channelId}),
    );
    return ChannelModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// トレンドのチャンネル一覧を取得する（channels/featured）
  Future<List<ChannelModel>> getChannelsFeatured() async {
    final res = await _dio.post('channels/featured', data: _body({}));
    return _toChannels(res.data);
  }

  /// お気に入りのチャンネル一覧を取得する（channels/my-favorites）
  Future<List<ChannelModel>> getChannelsMyFavorites() async {
    final res = await _dio.post('channels/my-favorites', data: _body({}));
    return _toChannels(res.data);
  }

  /// フォロー中のチャンネル一覧を取得する（channels/followed）
  Future<List<ChannelModel>> getChannelsFollowed({
    int limit = 30,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('channels/followed', data: _body(params));
    return _toChannels(res.data);
  }

  /// 管理中のチャンネル一覧を取得する（channels/owned）
  Future<List<ChannelModel>> getChannelsOwned({
    int limit = 30,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('channels/owned', data: _body(params));
    return _toChannels(res.data);
  }

  /// チャンネルを検索する（channels/search）
  Future<List<ChannelModel>> searchChannels({
    required String query,
    int limit = 20,
    String? untilId,
    String type = 'nameAndDescription',
  }) async {
    final params = <String, dynamic>{
      'query': query,
      'limit': limit,
      'type': type,
    };
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('channels/search', data: _body(params));
    return _toChannels(res.data);
  }

  /// チャンネルを作成する（channels/create）
  Future<ChannelModel> createChannel({
    required String name,
    String? description,
    String? bannerId,
    String color = '#000',
    bool? isSensitive,
    bool? allowRenoteToExternal,
  }) async {
    final params = <String, dynamic>{'name': name, 'color': color};
    if (description != null && description.isNotEmpty) {
      params['description'] = description;
    }
    if (bannerId != null) params['bannerId'] = bannerId;
    if (isSensitive != null) params['isSensitive'] = isSensitive;
    if (allowRenoteToExternal != null) {
      params['allowRenoteToExternal'] = allowRenoteToExternal;
    }
    final res = await _dio.post('channels/create', data: _body(params));
    return ChannelModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// チャンネル情報を更新する（channels/update）
  Future<ChannelModel> updateChannel({
    required String channelId,
    String? name,
    String? description,
    String? bannerId,
    String? color,
    bool? isArchived,
    bool? isSensitive,
    bool? allowRenoteToExternal,
  }) async {
    final params = <String, dynamic>{'channelId': channelId};
    if (name != null) params['name'] = name;
    if (description != null) params['description'] = description;
    if (bannerId != null) params['bannerId'] = bannerId;
    if (color != null) params['color'] = color;
    if (isArchived != null) params['isArchived'] = isArchived;
    if (isSensitive != null) params['isSensitive'] = isSensitive;
    if (allowRenoteToExternal != null) {
      params['allowRenoteToExternal'] = allowRenoteToExternal;
    }
    final res = await _dio.post('channels/update', data: _body(params));
    return ChannelModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// チャンネルをアーカイブ（削除相当）する（channels/update で isArchived: true）
  /// Misskey には channels/delete エンドポイントが存在しないため、
  /// アーカイブによって実質的にチャンネルを非公開にします。
  Future<void> archiveChannel(String channelId) async {
    await updateChannel(channelId: channelId, isArchived: true);
  }

  /// チャンネルをフォローする（channels/follow）
  Future<void> followChannel(String channelId) async {
    await _dio.post('channels/follow', data: _body({'channelId': channelId}));
  }

  /// チャンネルのフォローを解除する（channels/unfollow）
  Future<void> unfollowChannel(String channelId) async {
    await _dio.post('channels/unfollow', data: _body({'channelId': channelId}));
  }

  /// チャンネルをお気に入りに登録する（channels/favorite）
  Future<void> favoriteChannel(String channelId) async {
    await _dio.post('channels/favorite', data: _body({'channelId': channelId}));
  }

  /// チャンネルのお気に入りを解除する（channels/unfavorite）
  Future<void> unfavoriteChannel(String channelId) async {
    await _dio.post(
      'channels/unfavorite',
      data: _body({'channelId': channelId}),
    );
  }

  // ---- チャット（ダイレクトメッセージ） ----

  /// チャット履歴を取得する（chat/history）
  /// [room] が true の場合はルーム履歴、false の場合は1対1DM履歴
  Future<List<ChatMessageModel>> getChatHistory({
    bool room = false,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'room': room};
    final res = await _dio.post('chat/history', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ユーザーとの1対1チャットメッセージ一覧を取得する（chat/messages/user-timeline）
  Future<List<ChatMessageModel>> getChatUserTimeline({
    required String userId,
    int limit = 30,
    String? untilId,
    String? sinceId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (sinceId != null) params['sinceId'] = sinceId;
    final res = await _dio.post(
      'chat/messages/user-timeline',
      data: _body(params),
    );
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ルームのチャットメッセージ一覧を取得する（chat/messages/room-timeline）
  Future<List<ChatMessageModel>> getChatRoomTimeline({
    required String roomId,
    int limit = 30,
    String? untilId,
    String? sinceId,
  }) async {
    final params = <String, dynamic>{'roomId': roomId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    if (sinceId != null) params['sinceId'] = sinceId;
    final res = await _dio.post(
      'chat/messages/room-timeline',
      data: _body(params),
    );
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ユーザーにチャットメッセージを送信する（chat/messages/create-to-user）
  Future<ChatMessageModel> sendChatMessageToUser({
    required String toUserId,
    String? text,
    String? fileId,
  }) async {
    final params = <String, dynamic>{'toUserId': toUserId};
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (fileId != null) params['fileId'] = fileId;
    final res = await _dio.post(
      'chat/messages/create-to-user',
      data: _body(params),
    );
    return ChatMessageModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// ルームにチャットメッセージを送信する（chat/messages/create-to-room）
  Future<ChatMessageModel> sendChatMessageToRoom({
    required String toRoomId,
    String? text,
    String? fileId,
  }) async {
    final params = <String, dynamic>{'toRoomId': toRoomId};
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (fileId != null) params['fileId'] = fileId;
    final res = await _dio.post(
      'chat/messages/create-to-room',
      data: _body(params),
    );
    return ChatMessageModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// チャットメッセージを削除する（chat/messages/delete）
  Future<void> deleteChatMessage(String messageId) async {
    await _dio.post(
      'chat/messages/delete',
      data: _body({'messageId': messageId}),
    );
  }

  /// すべてのチャットを既読にする（chat/read-all）
  Future<void> readAllChats() async {
    await _dio.post('chat/read-all', data: _body({}));
  }

  /// 参加中のルーム一覧を取得する（chat/rooms/joining）
  ///
  /// このエンドポイントは `ChatRoomMembership`（`room` に [ChatRoomModel] を
  /// ネストして持つ）の配列を返すため、`room` を取り出して変換する。
  Future<List<ChatRoomModel>> getChatRoomsJoining({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('chat/rooms/joining', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map(
          (e) => (e as Map<String, dynamic>)['room'] as Map<String, dynamic>?,
        )
        .where((room) => room != null)
        .map((room) => ChatRoomModel.fromJson(room!))
        .toList();
  }

  /// 自分が作成（所有）したルーム一覧を取得する（chat/rooms/owned）
  ///
  /// `joining` には自分が所有するルームが含まれない場合があるため、
  /// ルーム一覧を網羅するには両方を取得してマージする。
  Future<List<ChatRoomModel>> getChatRoomsOwned({
    int limit = 30,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('chat/rooms/owned', data: _body(params));
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ChatRoomModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ルームの参加メンバー一覧を取得する（chat/rooms/members）
  ///
  /// `chat/rooms/members` は `ChatRoomMembership`（`user` に UserLite をネスト）の
  /// 配列を返すが、オーナーは membership を持たず含まれない場合がある。
  /// そのため `chat/rooms/show` でオーナーを取得し、先頭に補完する。
  Future<List<UserModel>> getChatRoomMembers({
    required String roomId,
    int limit = 100,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'roomId': roomId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;

    // メンバー一覧とルーム情報（オーナー補完用）を並行取得する。
    final results = await Future.wait([
      _dio.post('chat/rooms/members', data: _body(params)),
      _dio.post('chat/rooms/show', data: _body({'roomId': roomId})),
    ]);

    final memberList = (results[0].data as List<dynamic>)
        .map(
          (e) => (e as Map<String, dynamic>)['user'] as Map<String, dynamic>?,
        )
        .where((user) => user != null)
        .map((user) => UserModel.fromJson(user!, host: host))
        .toList();

    // オーナーが一覧に含まれていなければ先頭に追加する。
    final roomData = results[1].data as Map<String, dynamic>;
    final ownerData = roomData['owner'] as Map<String, dynamic>?;
    if (ownerData != null) {
      final owner = UserModel.fromJson(ownerData, host: host);
      if (!memberList.any((u) => u.id == owner.id)) {
        memberList.insert(0, owner);
      }
    }

    return memberList;
  }

  /// チャットルームを作成する（chat/rooms/create）
  Future<ChatRoomModel> createChatRoom({
    required String name,
    String? description,
  }) async {
    final params = <String, dynamic>{'name': name};
    if (description != null && description.isNotEmpty) {
      params['description'] = description;
    }
    final res = await _dio.post('chat/rooms/create', data: _body(params));
    return ChatRoomModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// チャットルームに招待する（chat/rooms/invitations/create）
  Future<void> inviteToChatRoom({
    required String roomId,
    required String userId,
  }) async {
    await _dio.post(
      'chat/rooms/invitations/create',
      data: _body({'roomId': roomId, 'userId': userId}),
    );
  }

  /// チャットルームから退出する（chat/rooms/leave）
  Future<void> leaveChatRoom(String roomId) async {
    await _dio.post('chat/rooms/leave', data: _body({'roomId': roomId}));
  }

  // ---- お気に入り（ノート） ----

  /// ノートの状態を取得する（notes/state）
  /// 戻り値: { isFavorited: bool, isMutedThread: bool }
  Future<NoteStateModel> getNoteState(String noteId) async {
    final res = await _dio.post('notes/state', data: _body({'noteId': noteId}));
    return NoteStateModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// ノートをお気に入りに追加する（notes/favorites/create）
  Future<void> createFavorite(String noteId) async {
    await _dio.post('notes/favorites/create', data: _body({'noteId': noteId}));
  }

  /// ノートをお気に入りから削除する（notes/favorites/delete）
  Future<void> deleteFavorite(String noteId) async {
    await _dio.post('notes/favorites/delete', data: _body({'noteId': noteId}));
  }

  /// お気に入り一覧を取得する（i/favorites）
  /// 戻り値: [{ id, createdAt, note: NoteObject }, ...]
  Future<List<NoteModel>> getFavorites({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('i/favorites', data: _body(params));
    final list = res.data as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      final noteMap = map['note'] as Map<String, dynamic>;
      return NoteModel.fromJson(noteMap, host: host);
    }).toList();
  }

  // ---- ページ ----

  List<PageModel> _parsePages(dynamic data) => (data as List<dynamic>)
      .map((e) => PageModel.fromJson(e as Map<String, dynamic>, host: host))
      .toList();

  /// ページを取得する（pages/show）
  ///
  /// [pageId] を指定するか、[name]（URLスラッグ）+ [username] の組を指定する。
  /// なお `pages/show` は**自インスタンスのページしか返さない**。
  Future<PageModel> getPage({
    String? pageId,
    String? name,
    String? username,
  }) async {
    assert(
      pageId != null || (name != null && username != null),
      'pageId、または name + username のいずれかを指定してください',
    );
    final params = <String, dynamic>{};
    if (pageId != null) {
      params['pageId'] = pageId;
    } else {
      params['name'] = name;
      params['username'] = username;
    }
    final res = await _dio.post('pages/show', data: _body(params));
    return PageModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  /// おすすめのページ一覧を取得する（pages/featured）
  /// **引数なし・固定10件**（いいね数降順）でページングは無い。
  Future<List<PageModel>> getFeaturedPages() async {
    final res = await _dio.post('pages/featured', data: _body({}));
    return _parsePages(res.data);
  }

  /// 自分のページ一覧を取得する（i/pages, `read:pages`）
  Future<List<PageModel>> getMyPages({int limit = 20, String? untilId}) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('i/pages', data: _body(params));
    return _parsePages(res.data);
  }

  /// 指定ユーザーのページ一覧を取得する（users/pages）
  Future<List<PageModel>> getUserPages({
    required String userId,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('users/pages', data: _body(params));
    return _parsePages(res.data);
  }

  /// いいねしたページ一覧を取得する（i/page-likes, `read:page-likes`）
  ///
  /// 戻り値は Page そのものではなく `{ id, page }` のラッパー配列。
  /// **ページングの `untilId` には外側の [PageLikeModel.id] を使うこと。**
  Future<List<PageLikeModel>> getLikedPages({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('i/page-likes', data: _body(params));
    return (res.data as List<dynamic>)
        .map(
          (e) =>
              PageLikeModel.fromJson(e as Map<String, dynamic>, host: host),
        )
        .toList();
  }

  /// ページを作成する（pages/create, `write:pages`）
  ///
  /// **レート制限が 10回/時**と厳しいため、エディタでは「新規作成は1回だけ、
  /// 以後は [updatePage]（300回/時）で保存」に統一すること。
  ///
  /// `content` / `variables` / `script` はすべてサーバー側で required。
  /// 廃止済み機能のフィールドだが、送らないと 400 になるため空値を必ず送る。
  ///
  /// [name] は同一ユーザー内でユニークで、重複すると `NAME_ALREADY_EXISTS`。
  Future<PageModel> createPage({
    required String title,
    required String name,
    required List<PageBlock> content,
    String? summary,
    String font = 'sans-serif',
    bool alignCenter = false,
    bool hideTitleWhenPinned = false,
    String? eyeCatchingImageId,
    List<dynamic> variables = const [],
    String script = '',
  }) async {
    final params = <String, dynamic>{
      'title': title,
      'name': name,
      'content': content.map((b) => b.toJson()).toList(),
      'variables': variables,
      'script': script,
      'font': font,
      'alignCenter': alignCenter,
      'hideTitleWhenPinned': hideTitleWhenPinned,
      'summary': summary,
    };
    if (eyeCatchingImageId != null) {
      params['eyeCatchingImageId'] = eyeCatchingImageId;
    }
    final res = await _dio.post('pages/create', data: _body(params));
    return PageModel.fromJson(res.data as Map<String, dynamic>, host: host);
  }

  /// ページを更新する（pages/update, `write:pages`）
  ///
  /// `pageId` 以外は部分更新で、**渡さなかったフィールドはサーバー側の値が維持される**。
  /// 逆に `summary` / `eyeCatchingImageId` は null を送ると消去されるため、
  /// 明示的に消したい場合は [clearSummary] / [clearEyeCatchingImage] を使う。
  ///
  /// 編集画面で読み込んだ `font` / `alignCenter` / `hideTitleWhenPinned` を
  /// 保持したまま渡さないと、往復で設定が失われる点に注意。
  Future<void> updatePage({
    required String pageId,
    String? title,
    String? name,
    String? summary,
    bool clearSummary = false,
    List<PageBlock>? content,
    String? font,
    bool? alignCenter,
    bool? hideTitleWhenPinned,
    String? eyeCatchingImageId,
    bool clearEyeCatchingImage = false,
    List<dynamic>? variables,
    String? script,
  }) async {
    final params = <String, dynamic>{'pageId': pageId};
    if (title != null) params['title'] = title;
    if (name != null) params['name'] = name;
    if (clearSummary) {
      params['summary'] = null;
    } else if (summary != null) {
      params['summary'] = summary;
    }
    if (content != null) {
      params['content'] = content.map((b) => b.toJson()).toList();
    }
    if (font != null) params['font'] = font;
    if (alignCenter != null) params['alignCenter'] = alignCenter;
    if (hideTitleWhenPinned != null) {
      params['hideTitleWhenPinned'] = hideTitleWhenPinned;
    }
    if (clearEyeCatchingImage) {
      params['eyeCatchingImageId'] = null;
    } else if (eyeCatchingImageId != null) {
      params['eyeCatchingImageId'] = eyeCatchingImageId;
    }
    if (variables != null) params['variables'] = variables;
    if (script != null) params['script'] = script;
    await _dio.post('pages/update', data: _body(params));
  }

  /// ページを削除する（pages/delete, `write:pages`）
  Future<void> deletePage(String pageId) async {
    await _dio.post('pages/delete', data: _body({'pageId': pageId}));
  }

  /// ページにいいねする（pages/like, `write:page-likes`）
  /// 自分のページには `YOUR_PAGE` エラーでいいねできない。
  Future<void> likePage(String pageId) async {
    await _dio.post('pages/like', data: _body({'pageId': pageId}));
  }

  /// ページのいいねを解除する（pages/unlike, `write:page-likes`）
  Future<void> unlikePage(String pageId) async {
    await _dio.post('pages/unlike', data: _body({'pageId': pageId}));
  }

  // ---- ギャラリー ----

  List<GalleryPostModel> _parseGalleryPosts(dynamic data) =>
      (data as List<dynamic>)
          .map(
            (e) => GalleryPostModel.fromJson(
              e as Map<String, dynamic>,
              host: host,
            ),
          )
          .toList();

  /// 新着のギャラリー投稿一覧を取得する（gallery/posts）
  Future<List<GalleryPostModel>> getGalleryPosts({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('gallery/posts', data: _body(params));
    return _parseGalleryPosts(res.data);
  }

  /// おすすめのギャラリー投稿一覧を取得する（gallery/featured）
  /// このエンドポイントは `untilId` のみ対応（`sinceId` は無い）。
  Future<List<GalleryPostModel>> getFeaturedGalleryPosts({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('gallery/featured', data: _body(params));
    return _parseGalleryPosts(res.data);
  }

  /// 人気のギャラリー投稿一覧を取得する（gallery/popular）
  /// **引数なし・固定10件**でページングは無い（読み切り + Pull-to-Refresh 向け）。
  Future<List<GalleryPostModel>> getPopularGalleryPosts() async {
    final res = await _dio.post('gallery/popular', data: _body({}));
    return _parseGalleryPosts(res.data);
  }

  /// ギャラリー投稿を取得する（gallery/posts/show）
  Future<GalleryPostModel> getGalleryPost(String postId) async {
    final res = await _dio.post(
      'gallery/posts/show',
      data: _body({'postId': postId}),
    );
    return GalleryPostModel.fromJson(
      res.data as Map<String, dynamic>,
      host: host,
    );
  }

  /// 指定ユーザーのギャラリー投稿一覧を取得する（users/gallery/posts）
  Future<List<GalleryPostModel>> getUserGalleryPosts({
    required String userId,
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'userId': userId, 'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('users/gallery/posts', data: _body(params));
    return _parseGalleryPosts(res.data);
  }

  /// 自分のギャラリー投稿一覧を取得する（i/gallery/posts, `read:gallery`）
  Future<List<GalleryPostModel>> getMyGalleryPosts({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('i/gallery/posts', data: _body(params));
    return _parseGalleryPosts(res.data);
  }

  /// いいねしたギャラリー投稿一覧を取得する（i/gallery/likes, `read:gallery-likes`）
  ///
  /// 戻り値は `{ id, post }` のラッパー配列。
  /// **ページングの `untilId` には外側の [GalleryLikeModel.id] を使うこと。**
  Future<List<GalleryLikeModel>> getLikedGalleryPosts({
    int limit = 20,
    String? untilId,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (untilId != null) params['untilId'] = untilId;
    final res = await _dio.post('i/gallery/likes', data: _body(params));
    return (res.data as List<dynamic>)
        .map(
          (e) => GalleryLikeModel.fromJson(
            e as Map<String, dynamic>,
            host: host,
          ),
        )
        .toList();
  }

  /// ギャラリーに投稿する（gallery/posts/create, `write:gallery`）
  ///
  /// **レート制限は 20回/時。** [fileIds] は既にドライブに存在するファイルの ID で、
  /// 1〜32個・重複不可。端末の画像から投稿する場合は [uploadFile] で
  /// ドライブへ上げてから ID を渡す。
  ///
  /// タグはパラメータに存在せず、サーバーが [description] 内のハッシュタグから
  /// 自動抽出する。
  Future<GalleryPostModel> createGalleryPost({
    required String title,
    required List<String> fileIds,
    String? description,
    bool isSensitive = false,
  }) async {
    final params = <String, dynamic>{
      'title': title,
      'fileIds': fileIds,
      'isSensitive': isSensitive,
    };
    if (description != null && description.isNotEmpty) {
      params['description'] = description;
    }
    final res = await _dio.post('gallery/posts/create', data: _body(params));
    return GalleryPostModel.fromJson(
      res.data as Map<String, dynamic>,
      host: host,
    );
  }

  /// ギャラリー投稿を更新する（gallery/posts/update, `write:gallery`）
  ///
  /// 部分更新（300回/時）。編集画面からは [title] / [fileIds] も含めて
  /// 現在値を渡すこと（サーバー実装によっては必須扱いになる）。
  /// [description] は null を送ると消去されるため、明示的に消す場合は
  /// [clearDescription] を使う。
  Future<GalleryPostModel> updateGalleryPost({
    required String postId,
    String? title,
    List<String>? fileIds,
    String? description,
    bool clearDescription = false,
    bool? isSensitive,
  }) async {
    final params = <String, dynamic>{'postId': postId};
    if (title != null) params['title'] = title;
    if (fileIds != null) params['fileIds'] = fileIds;
    if (clearDescription) {
      params['description'] = null;
    } else if (description != null) {
      params['description'] = description;
    }
    if (isSensitive != null) params['isSensitive'] = isSensitive;
    final res = await _dio.post('gallery/posts/update', data: _body(params));
    return GalleryPostModel.fromJson(
      res.data as Map<String, dynamic>,
      host: host,
    );
  }

  /// ギャラリー投稿を削除する（gallery/posts/delete, `write:gallery`）
  Future<void> deleteGalleryPost(String postId) async {
    await _dio.post('gallery/posts/delete', data: _body({'postId': postId}));
  }

  /// ギャラリー投稿にいいねする（gallery/posts/like, `write:gallery-likes`）
  /// 自分の投稿には `YOUR_POST` エラーでいいねできない。
  Future<void> likeGalleryPost(String postId) async {
    await _dio.post('gallery/posts/like', data: _body({'postId': postId}));
  }

  /// ギャラリー投稿のいいねを解除する（gallery/posts/unlike, `write:gallery-likes`）
  Future<void> unlikeGalleryPost(String postId) async {
    await _dio.post('gallery/posts/unlike', data: _body({'postId': postId}));
  }
}
