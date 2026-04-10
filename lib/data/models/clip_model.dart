class ClipModel {
  final String id;
  final DateTime createdAt;
  final String name;
  final String? description;
  final bool isPublic;
  final int? notesCount;

  const ClipModel({
    required this.id,
    required this.createdAt,
    required this.name,
    this.description,
    required this.isPublic,
    this.notesCount,
  });

  factory ClipModel.fromJson(Map<String, dynamic> json) {
    return ClipModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      name: json['name'] as String,
      description: json['description'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      notesCount: json['notesCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'name': name,
    'description': description,
    'isPublic': isPublic,
    if (notesCount != null) 'notesCount': notesCount,
  };
}
