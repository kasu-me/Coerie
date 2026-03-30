import 'user_model.dart';

class DriveFileModel {
  final String id;
  final String name;
  final String type;
  final String url;
  final String? thumbnailUrl;
  final int size;

  const DriveFileModel({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    required this.size,
  });

  bool get isImage => type.startsWith('image/');
  bool get isVideo => type.startsWith('video/');

  factory DriveFileModel.fromJson(Map<String, dynamic> json) {
    return DriveFileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      size: json['size'] as int? ?? 0,
    );
  }
}

class NoteModel {
  final String id;
  final DateTime createdAt;
  final UserModel user;
  final String? text;
  final String visibility;
  final List<DriveFileModel> files;
  final int repliesCount;
  final int renoteCount;
  final Map<String, int> reactions;
  final NoteModel? reply;
  final NoteModel? renote;

  const NoteModel({
    required this.id,
    required this.createdAt,
    required this.user,
    this.text,
    required this.visibility,
    this.files = const [],
    this.repliesCount = 0,
    this.renoteCount = 0,
    this.reactions = const {},
    this.reply,
    this.renote,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    final filesJson = json['files'] as List<dynamic>? ?? [];
    final reactionsJson = json['reactions'] as Map<String, dynamic>? ?? {};

    return NoteModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: UserModel.fromJson(
        json['user'] as Map<String, dynamic>,
        host: host,
      ),
      text: json['text'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      files: filesJson
          .map((f) => DriveFileModel.fromJson(f as Map<String, dynamic>))
          .toList(),
      repliesCount: json['repliesCount'] as int? ?? 0,
      renoteCount: json['renoteCount'] as int? ?? 0,
      reactions: reactionsJson.map((k, v) => MapEntry(k, v as int)),
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
    );
  }
}
