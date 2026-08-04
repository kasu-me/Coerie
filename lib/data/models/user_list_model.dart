import 'user_model.dart';

/// Misskey のユーザーリスト（users/lists/*）。
class UserListModel {
  final String id;
  final String name;
  final bool isPublic;

  /// リストに含まれるユーザーの id。`users/lists/list` のみが返す。
  final List<String> userIds;

  const UserListModel({
    required this.id,
    required this.name,
    this.isPublic = false,
    this.userIds = const [],
  });

  factory UserListModel.fromJson(Map<String, dynamic> json) {
    return UserListModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isPublic: json['isPublic'] as bool? ?? false,
      userIds:
          (json['userIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

/// リストへの所属（`users/lists/get-memberships` の要素）。
///
/// リストからの削除は所属ではなくユーザーを指定するため、[user] を保持する。
class UserListMembershipModel {
  final String id;
  final String userId;
  final UserModel? user;

  const UserListMembershipModel({
    required this.id,
    required this.userId,
    this.user,
  });

  factory UserListMembershipModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return UserListMembershipModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      user: user == null ? null : UserModel.fromJson(user),
    );
  }
}
