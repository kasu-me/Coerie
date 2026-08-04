/// Misskey のチャンネル（channels/*）。
///
/// `channels/show` は閲覧者との関係（[isFollowing] / [isFavorited]）を含むが、
/// `channels/featured` などの一覧系は含まないことがあるため、
/// 関係フィールドは既定値を持たせている。
class ChannelModel {
  final String id;
  final String name;
  final String? description;
  final String? bannerUrl;

  /// `#RRGGBB` 形式のテーマカラー。既定値は画面ごとに異なるため null のまま保持する。
  final String? color;

  final int usersCount;
  final int notesCount;

  /// チャンネルの作成者。所有者判定に使う。
  final String? userId;

  final bool isArchived;
  final bool isSensitive;
  final bool allowRenoteToExternal;
  final bool isFollowing;
  final bool isFavorited;

  const ChannelModel({
    required this.id,
    required this.name,
    this.description,
    this.bannerUrl,
    this.color,
    this.usersCount = 0,
    this.notesCount = 0,
    this.userId,
    this.isArchived = false,
    this.isSensitive = false,
    this.allowRenoteToExternal = true,
    this.isFollowing = false,
    this.isFavorited = false,
  });

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      color: json['color'] as String?,
      usersCount: json['usersCount'] as int? ?? 0,
      notesCount: json['notesCount'] as int? ?? 0,
      userId: json['userId'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      isSensitive: json['isSensitive'] as bool? ?? false,
      allowRenoteToExternal: json['allowRenoteToExternal'] as bool? ?? true,
      isFollowing: json['isFollowing'] as bool? ?? false,
      isFavorited: json['isFavorited'] as bool? ?? false,
    );
  }
}
