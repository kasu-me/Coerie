import 'user_model.dart';

/// メンション補完で優先表示するための「過去にリプライ／メンションを送った相手」1件分。
///
/// 補完バーはキーストロークごとに描画されるため、表示に必要な情報だけを写して持つ。
/// こうしておくと履歴分の候補を API 応答を待たずに即座に出せる。
class MentionHistoryEntry {
  final String userId;
  final String username;

  /// ユーザーのホスト。ローカルユーザーの場合はアカウントのホストが入る
  /// （[UserModel.fromJson] が `host: null` をアカウントのホストで補うため）。
  final String host;
  final String name;
  final String? avatarUrl;

  const MentionHistoryEntry({
    required this.userId,
    required this.username,
    required this.host,
    required this.name,
    this.avatarUrl,
  });

  factory MentionHistoryEntry.fromUser(UserModel user) => MentionHistoryEntry(
    userId: user.id,
    username: user.username,
    host: user.host,
    name: user.name,
    avatarUrl: user.avatarUrl,
  );

  /// 補完バーは API 応答と履歴を同じ型で並べるため、[UserModel] に戻して渡す。
  UserModel toUserModel() => UserModel(
    id: userId,
    name: name,
    username: username,
    host: host,
    avatarUrl: avatarUrl,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'host': host,
    'name': name,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  factory MentionHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MentionHistoryEntry(
        userId: json['userId'] as String,
        username: json['username'] as String,
        host: json['host'] as String? ?? '',
        name: json['name'] as String? ?? json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );
}
