class DriveFileModel {
  final String id;
  final String name;
  final String type;
  final String url;
  final String? thumbnailUrl;
  final int size;
  final DateTime createdAt;

  const DriveFileModel({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    required this.size,
    required this.createdAt,
  });

  bool get isImage => type.startsWith('image/');

  factory DriveFileModel.fromJson(Map<String, dynamic> json) {
    return DriveFileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      size: json['size'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
