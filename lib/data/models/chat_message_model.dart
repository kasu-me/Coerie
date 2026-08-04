import 'chat_room_model.dart';
import 'user_model.dart';

/// Misskey チャット（chat/*）のメッセージモデル。
///
/// chat API は用途によって返すスキーマが異なる:
/// - `chat/history`          : 完全な `ChatMessage`（fromUser/toUser/toRoom/isRead を含む）
/// - `chat/messages/user-timeline` : `ChatMessageLiteFor1on1`（fromUser/toUser を含まず ID のみ）
/// - `chat/messages/room-timeline` : `ChatMessageLiteForRoom`（fromUser は含むが toRoom は含まない）
///
/// いずれのスキーマも欠けたフィールドは null として扱えるよう、すべて nullable で保持する。
class ChatMessageModel {
  final String id;
  final DateTime createdAt;
  final String? text;
  final String? fileId;
  final Map<String, dynamic>? file;

  /// 送信者
  final String fromUserId;
  final UserModel? fromUser;

  /// 1対1 DM の宛先（ルームメッセージでは null）
  final String? toUserId;
  final UserModel? toUser;

  /// ルームメッセージの宛先（DM では null）
  final String? toRoomId;
  final ChatRoomModel? toRoom;

  /// 既読フラグ（`ChatMessage` のみ。Lite スキーマには含まれない）
  final bool isRead;

  /// リアクション一覧（`{ reaction, user, ... }` の配列）
  final List<dynamic> reactions;

  const ChatMessageModel({
    required this.id,
    required this.createdAt,
    this.text,
    this.fileId,
    this.file,
    required this.fromUserId,
    this.fromUser,
    this.toUserId,
    this.toUser,
    this.toRoomId,
    this.toRoom,
    this.isRead = false,
    this.reactions = const [],
  });

  bool get isDirectMessage => toUserId != null;
  bool get isRoomMessage => toRoomId != null;

  String get senderName => fromUser?.name ?? '不明';

  String? get senderAvatarUrl => fromUser?.avatarUrl;

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['createdAt'] as String?;
    final fromUser = json['fromUser'] as Map<String, dynamic>?;
    final toUser = json['toUser'] as Map<String, dynamic>?;
    final toRoom = json['toRoom'] as Map<String, dynamic>?;
    return ChatMessageModel(
      id: json['id'] as String? ?? '',
      createdAt: rawCreatedAt != null
          ? DateTime.parse(rawCreatedAt).toLocal()
          : DateTime.now(),
      text: json['text'] as String?,
      fileId: json['fileId'] as String?,
      file: json['file'] as Map<String, dynamic>?,
      fromUserId: json['fromUserId'] as String? ?? '',
      fromUser: fromUser == null ? null : UserModel.fromJson(fromUser),
      toUserId: json['toUserId'] as String?,
      toUser: toUser == null ? null : UserModel.fromJson(toUser),
      toRoomId: json['toRoomId'] as String?,
      toRoom: toRoom == null ? null : ChatRoomModel.fromJson(toRoom),
      isRead: json['isRead'] as bool? ?? false,
      reactions: json['reactions'] as List<dynamic>? ?? const [],
    );
  }
}
