/// ドライブ上のファイル（Misskey の DriveFile）。
///
/// ノートの添付ファイル・ギャラリー投稿・ページのブロックで共通して使う。
/// 下書き（DraftModel）では [toJson] / [DriveFileModel.fromJson] の結果が Hive に
/// 永続化されるため、フィールドを増やすときは必ず既定値を持たせること
/// （旧レコードには値が存在しない）。
class DriveFileModel {
  final String id;
  final String name;
  final String type;
  final String url;
  final String? thumbnailUrl;
  final int size;
  final bool isSensitive;

  /// アップロード日時。ノートの添付として取得した場合や、
  /// 旧形式の下書きから復元した場合は欠けるため nullable。
  final DateTime? createdAt;

  const DriveFileModel({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    required this.size,
    this.isSensitive = false,
    this.createdAt,
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
    'createdAt': createdAt?.toIso8601String(),
  };

  factory DriveFileModel.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'] as String?;
    return DriveFileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      size: json['size'] as int? ?? 0,
      isSensitive: json['isSensitive'] as bool? ?? false,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
    );
  }
}
