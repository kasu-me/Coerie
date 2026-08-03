class ClipModel {
  final String id;
  final DateTime createdAt;
  final String? userId;
  final String name;
  final String? description;
  final bool isPublic;
  final int? notesCount;
  final int? favoritedCount;

  /// 自分がお気に入りに登録しているか。未認証時は API が返さないため null。
  final bool? isFavorited;

  const ClipModel({
    required this.id,
    required this.createdAt,
    this.userId,
    required this.name,
    this.description,
    required this.isPublic,
    this.notesCount,
    this.favoritedCount,
    this.isFavorited,
  });

  factory ClipModel.fromJson(Map<String, dynamic> json) {
    return ClipModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      userId: json['userId'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      notesCount: json['notesCount'] as int?,
      favoritedCount: json['favoritedCount'] as int?,
      isFavorited: json['isFavorited'] as bool?,
    );
  }

  ClipModel copyWith({
    String? name,
    String? description,
    bool? isPublic,
    int? notesCount,
    int? favoritedCount,
    bool? isFavorited,
  }) {
    return ClipModel(
      id: id,
      createdAt: createdAt,
      userId: userId,
      name: name ?? this.name,
      description: description ?? this.description,
      isPublic: isPublic ?? this.isPublic,
      notesCount: notesCount ?? this.notesCount,
      favoritedCount: favoritedCount ?? this.favoritedCount,
      isFavorited: isFavorited ?? this.isFavorited,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    if (userId != null) 'userId': userId,
    'name': name,
    'description': description,
    'isPublic': isPublic,
    if (notesCount != null) 'notesCount': notesCount,
    if (favoritedCount != null) 'favoritedCount': favoritedCount,
    if (isFavorited != null) 'isFavorited': isFavorited,
  };
}
