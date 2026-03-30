import 'note_model.dart';
import 'user_model.dart';

class NotificationModel {
  final String id;
  final String type; // follow, mention, reply, renote, reaction, etc.
  final DateTime createdAt;
  final bool isRead;
  final UserModel? user;
  final NoteModel? note;
  final String? reaction; // type == 'reaction' のとき

  const NotificationModel({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.user,
    this.note,
    this.reaction,
  });

  factory NotificationModel.fromJson(
    Map<String, dynamic> json, {
    String host = '',
  }) {
    return NotificationModel(
      id: json['id'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      user: json['user'] != null
          ? UserModel.fromJson(json['user'] as Map<String, dynamic>, host: host)
          : null,
      note: json['note'] != null
          ? NoteModel.fromJson(json['note'] as Map<String, dynamic>, host: host)
          : null,
      reaction: json['reaction'] as String?,
    );
  }
}
