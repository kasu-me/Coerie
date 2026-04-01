class UserModel {
  final String id;
  final String name;
  final String username;
  final String host;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? followingCount;
  final int? followersCount;
  final int? notesCount;
  final String? description;
  final List<String> pinnedNoteIds;
  final bool isFollowing;
  final bool isFollowed;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.host,
    this.avatarUrl,
    this.bannerUrl,
    this.followingCount,
    this.followersCount,
    this.notesCount,
    this.description,
    this.pinnedNoteIds = const [],
    this.isFollowing = false,
    this.isFollowed = false,
  });

  String get acct => host.isEmpty ? '@$username' : '@$username@$host';

  factory UserModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['username'] as String,
      username: json['username'] as String,
      host: json['host'] as String? ?? host,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      followingCount: json['followingCount'] as int?,
      followersCount: json['followersCount'] as int?,
      notesCount: json['notesCount'] as int?,
      description: json['description'] as String?,
      pinnedNoteIds:
          (json['pinnedNoteIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      isFollowing: json['isFollowing'] as bool? ?? false,
      isFollowed: json['isFollowed'] as bool? ?? false,
    );
  }
}
