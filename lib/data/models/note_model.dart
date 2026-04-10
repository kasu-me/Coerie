import 'user_model.dart';

class DriveFileModel {
  final String id;
  final String name;
  final String type;
  final String url;
  final String? thumbnailUrl;
  final int size;
  final bool isSensitive;

  const DriveFileModel({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    required this.size,
    this.isSensitive = false,
  });

  bool get isImage => type.startsWith('image/');
  bool get isVideo => type.startsWith('video/');
  bool get isAudio => type.startsWith('audio/');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'url': url,
    'thumbnailUrl': thumbnailUrl,
    'size': size,
    'isSensitive': isSensitive,
  };

  factory DriveFileModel.fromJson(Map<String, dynamic> json) {
    return DriveFileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      size: json['size'] as int? ?? 0,
      isSensitive: json['isSensitive'] as bool? ?? false,
    );
  }
}

class NoteModel {
  final String id;
  final DateTime createdAt;
  final UserModel user;
  final String? text;
  final String? cw;
  final String visibility;
  final List<DriveFileModel> files;
  final int repliesCount;
  final int renoteCount;
  final Map<String, int> reactions;
  final String? myReaction;

  /// ノート本文で使われているカスタム絵文字の name→url マップ（Misskey API の emojis フィールド）
  final Map<String, String> emojis;

  /// リアクションで使われているカスタム絵文字の name→url マップ（reactionEmojis フィールド、リモート含む）
  final Map<String, String> reactionEmojis;
  final NoteModel? reply;
  final NoteModel? renote;

  /// ノートのローカル公開URL（例: https://host/notes/id）
  final String? url;

  /// リモートノートの ActivityPub URI（リモートアカウントのノートのみ）
  final String? uri;

  const NoteModel({
    required this.id,
    required this.createdAt,
    required this.user,
    this.text,
    this.cw,
    required this.visibility,
    this.files = const [],
    this.repliesCount = 0,
    this.renoteCount = 0,
    this.reactions = const {},
    this.myReaction,
    this.emojis = const {},
    this.reactionEmojis = const {},
    this.reply,
    this.renote,
    this.url,
    this.uri,
  });

  static const _sentinel = Object();

  NoteModel copyWith({
    Map<String, int>? reactions,
    Object? myReaction = _sentinel,
    int? repliesCount,
    int? renoteCount,
  }) => NoteModel(
    id: id,
    createdAt: createdAt,
    user: user,
    text: text,
    cw: cw,
    visibility: visibility,
    files: files,
    repliesCount: repliesCount ?? this.repliesCount,
    renoteCount: renoteCount ?? this.renoteCount,
    reactions: reactions ?? this.reactions,
    myReaction: identical(myReaction, _sentinel)
        ? this.myReaction
        : myReaction as String?,
    emojis: emojis,
    reactionEmojis: reactionEmojis,
    reply: reply,
    renote: renote,
    url: url,
    uri: uri,
  );

  factory NoteModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    final filesJson = json['files'] as List<dynamic>? ?? [];
    final reactionsJson = json['reactions'] as Map<String, dynamic>? ?? {};

    // emojis フィールド: Map<String,String> 形式（Misskey 13+）またはリスト形式
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

    return NoteModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: UserModel.fromJson(
        json['user'] as Map<String, dynamic>,
        host: host,
      ),
      text: json['text'] as String?,
      cw: json['cw'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      files: filesJson
          .map((f) => DriveFileModel.fromJson(f as Map<String, dynamic>))
          .toList(),
      repliesCount: json['repliesCount'] as int? ?? 0,
      renoteCount: json['renoteCount'] as int? ?? 0,
      reactions: reactionsJson.map((k, v) => MapEntry(k, v as int)),
      myReaction: json['myReaction'] as String?,
      emojis: parseEmojiMap(json['emojis']),
      reactionEmojis: parseEmojiMap(json['reactionEmojis']),
      reply: json['reply'] != null
          ? NoteModel.fromJson(
              json['reply'] as Map<String, dynamic>,
              host: host,
            )
          : null,
      renote: json['renote'] != null
          ? NoteModel.fromJson(
              json['renote'] as Map<String, dynamic>,
              host: host,
            )
          : null,
      url: json['url'] as String?,
      uri: json['uri'] as String?,
    );
  }
}
