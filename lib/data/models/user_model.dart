class UserModel {
  final String id;
  final String name;
  final String username;
  final String host;
  final String? avatarUrl;
  final int followingCount;
  final int followersCount;
  final String? bio;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.host,
    this.avatarUrl,
    this.followingCount = 0,
    this.followersCount = 0,
    this.bio,
  });

  String get acct => host.isEmpty ? '@$username' : '@$username@$host';

  factory UserModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['username'] as String,
      username: json['username'] as String,
      host: json['host'] as String? ?? host,
      avatarUrl: json['avatarUrl'] as String?,
      followingCount: json['followingCount'] as int? ?? 0,
      followersCount: json['followersCount'] as int? ?? 0,
      bio: json['description'] as String?,
    );
  }
}
