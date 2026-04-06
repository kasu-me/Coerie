class AnnouncementModel {
  final String id;
  final String? title;
  final String? text;
  final DateTime createdAt;
  final String? url;
  final bool pinned;
  final bool isRead;

  const AnnouncementModel({
    required this.id,
    this.title,
    this.text,
    required this.createdAt,
    this.url,
    this.pinned = false,
    this.isRead = false,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] as String,
      title: json['title'] as String?,
      text: json['text'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      url: json['url'] as String?,
      pinned: json['pinned'] as bool? ?? json['isPinned'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  AnnouncementModel copyWith({
    String? id,
    String? title,
    String? text,
    DateTime? createdAt,
    String? url,
    bool? pinned,
    bool? isRead,
  }) {
    return AnnouncementModel(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      url: url ?? this.url,
      pinned: pinned ?? this.pinned,
      isRead: isRead ?? this.isRead,
    );
  }
}
