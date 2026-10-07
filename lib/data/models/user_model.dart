import 'user_field_model.dart';

class UserModel {
  final String id;
  final String name;
  final String username;
  final String host;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? followingCount;
  final int? followersCount;
  final int? notesCount;
  final String? description;
  final List<String> pinnedNoteIds;
  final List<UserFieldModel> fields;
  final bool isFollowing;
  final bool isFollowed;
  final bool isBlocking;
  final bool isMuted;
  final bool isLocked;

  /// リアクション一覧（`users/reactions`）を他人に公開しているか。
  /// `users/show` などの詳細版レスポンスにしか含まれないため、
  /// ノートに埋め込まれたユーザー等では常に false になる。
  final bool publicReactions;

  /// 名前・自己紹介・フィールドに使われているカスタム絵文字の name→url マップ（Misskey API の emojis フィールド）。
  /// リモートユーザーの絵文字は接続先インスタンスの絵文字一覧で引けないため、これで解決する。
  final Map<String, String> emojis;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.host,
    this.avatarUrl,
    this.bannerUrl,
    this.followingCount,
    this.followersCount,
    this.notesCount,
    this.description,
    this.pinnedNoteIds = const [],
    this.fields = const [],
    this.isFollowing = false,
    this.isFollowed = false,
    this.isBlocking = false,
    this.isMuted = false,
    this.isLocked = false,
    this.publicReactions = false,
    this.emojis = const {},
  });

  String get acct => host.isEmpty ? '@$username' : '@$username@$host';

  /// 表示名。未設定（空文字）の場合はユーザー名にフォールバックする
  String get displayName => name.isEmpty ? username : name;

  factory UserModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['username'] as String,
      username: json['username'] as String,
      host: json['host'] as String? ?? host,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      followingCount: json['followingCount'] as int?,
      followersCount: json['followersCount'] as int?,
      notesCount: json['notesCount'] as int?,
      description: json['description'] as String?,
      pinnedNoteIds:
          (json['pinnedNoteIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      fields:
          (json['fields'] as List<dynamic>?)
              ?.map((e) => UserFieldModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      isFollowing: json['isFollowing'] as bool? ?? false,
      isFollowed: json['isFollowed'] as bool? ?? false,
      isBlocking: json['isBlocking'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      publicReactions: json['publicReactions'] as bool? ?? false,
      emojis: parseEmojiMap(json['emojis']),
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? username,
    String? host,
    String? avatarUrl,
    String? bannerUrl,
    int? followingCount,
    int? followersCount,
    int? notesCount,
    String? description,
    List<String>? pinnedNoteIds,
    List<UserFieldModel>? fields,
    bool? isFollowing,
    bool? isFollowed,
    bool? isBlocking,
    bool? isMuted,
    bool? isLocked,
    bool? publicReactions,
    Map<String, String>? emojis,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      host: host ?? this.host,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      followingCount: followingCount ?? this.followingCount,
      followersCount: followersCount ?? this.followersCount,
      notesCount: notesCount ?? this.notesCount,
      description: description ?? this.description,
      pinnedNoteIds: pinnedNoteIds ?? this.pinnedNoteIds,
      fields: fields ?? this.fields,
      isFollowing: isFollowing ?? this.isFollowing,
      isFollowed: isFollowed ?? this.isFollowed,
      isBlocking: isBlocking ?? this.isBlocking,
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
      publicReactions: publicReactions ?? this.publicReactions,
      emojis: emojis ?? this.emojis,
    );
  }
}

/// Misskey API の emojis 系フィールドを name→url マップに変換する。
/// Misskey 13 以降は Map 形式だが、古いサーバーはリスト形式で返すため両方受け付ける。
Map<String, String> parseEmojiMap(dynamic raw) {
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k as String, v as String));
  }
  if (raw is List) {
    return {
      for (final e in raw)
        if (e is Map && e['name'] != null && e['url'] != null)
          e['name'] as String: e['url'] as String,
    };
  }
  return {};
}

/// `users/following` / `users/followers` の戻り値のラッパー
/// （`{ id, createdAt, followee }` または `{ id, createdAt, follower }`）。
///
/// [user] はエンドポイントに応じてフォローされている側／している側になる。
///
/// **ページングのカーソルには [UserModel.id] ではなく、フォロー関係レコードの
/// [id] を使うこと。** `user.id` を使うとページングが壊れる。
///
/// フォロー関係レコードの ID は「フォローした時刻」から、ユーザーの ID は
/// 「アカウントを作成した時刻」から採番される。どちらも同じ aid 形式なので
/// サーバーはエラーを返さず、アカウント作成日時を基準に切った別の窓が
/// 返ってくるため、2ページ目以降で重複・欠落が静かに起きる。
class FollowingModel {
  final String id;
  final UserModel user;

  const FollowingModel({required this.id, required this.user});

  /// [userKey] は `users/following` なら `'followee'`、
  /// `users/followers` なら `'follower'`。
  factory FollowingModel.fromJson(
    Map<String, dynamic> json, {
    required String userKey,
    String host = '',
  }) {
    return FollowingModel(
      id: json['id'] as String,
      user: UserModel.fromJson(
        json[userKey] as Map<String, dynamic>,
        host: host,
      ),
    );
  }

  FollowingModel copyWith({UserModel? user}) =>
      FollowingModel(id: id, user: user ?? this.user);
}
