/// Misskey チャットルーム（chat/rooms/*）のモデル。
///
/// `ChatRoom` スキーマに準拠する。`chat/rooms/joining` は `ChatRoomMembership`
/// （`room` フィールドにこの `ChatRoom` をネストして持つ）を返すため、
/// パース側で `membership['room']` を取り出してから本モデルに変換する。
class ChatRoomModel {
  final String id;
  final DateTime? createdAt;
  final String name;
  final String description;
  final String ownerId;
  final Map<String, dynamic>? owner;
  final bool isMuted;
  final bool invitationExists;

  const ChatRoomModel({
    required this.id,
    this.createdAt,
    required this.name,
    this.description = '',
    required this.ownerId,
    this.owner,
    this.isMuted = false,
    this.invitationExists = false,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['createdAt'] as String?;
    return ChatRoomModel(
      id: json['id'] as String? ?? '',
      createdAt: rawCreatedAt != null
          ? DateTime.tryParse(rawCreatedAt)?.toLocal()
          : null,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      owner: json['owner'] as Map<String, dynamic>?,
      isMuted: json['isMuted'] as bool? ?? false,
      invitationExists: json['invitationExists'] as bool? ?? false,
    );
  }
}
