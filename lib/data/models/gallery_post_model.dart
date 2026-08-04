import 'drive_file_model.dart';
import 'user_model.dart';

/// ギャラリー投稿（画像作品の投稿）。
class GalleryPostModel {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;
  final UserModel? user;

  final String title;
  final String? description;

  final List<String> fileIds;

  /// 添付画像の実体（1〜32枚）。
  final List<DriveFileModel> files;

  /// **タグは `description` 内のハッシュタグからサーバーが自動抽出する。**
  /// create / update のパラメータには存在しないため、UI 上は表示専用。
  final List<String> tags;

  /// センシティブ判定は**投稿単位**（ファイル単位ではない）。
  final bool isSensitive;

  final int likedCount;

  /// 未認証時は API が返さないため null。
  final bool? isLiked;

  const GalleryPostModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.user,
    required this.title,
    this.description,
    this.fileIds = const [],
    this.files = const [],
    this.tags = const [],
    this.isSensitive = false,
    this.likedCount = 0,
    this.isLiked,
  });

  factory GalleryPostModel.fromJson(
    Map<String, dynamic> json, {
    String host = '',
  }) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final userJson = json['user'];
    final files =
        (json['files'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(DriveFileModel.fromJson)
            .toList() ??
        const <DriveFileModel>[];
    return GalleryPostModel(
      id: json['id'] as String,
      createdAt: createdAt,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : createdAt,
      userId: json['userId'] as String? ?? '',
      user: userJson is Map<String, dynamic>
          ? UserModel.fromJson(userJson, host: host)
          : null,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      // fileIds が省略される応答があるため、files から補完する。
      fileIds:
          (json['fileIds'] as List<dynamic>?)?.cast<String>() ??
          files.map((f) => f.id).toList(),
      files: files,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      isSensitive: json['isSensitive'] as bool? ?? false,
      likedCount: json['likedCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool?,
    );
  }

  GalleryPostModel copyWith({
    String? title,
    String? description,
    List<String>? fileIds,
    List<DriveFileModel>? files,
    List<String>? tags,
    bool? isSensitive,
    int? likedCount,
    bool? isLiked,
  }) {
    return GalleryPostModel(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      userId: userId,
      user: user,
      title: title ?? this.title,
      description: description ?? this.description,
      fileIds: fileIds ?? this.fileIds,
      files: files ?? this.files,
      tags: tags ?? this.tags,
      isSensitive: isSensitive ?? this.isSensitive,
      likedCount: likedCount ?? this.likedCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

/// `i/gallery/likes` の戻り値のラッパー。
///
/// **ページングのカーソルには [GalleryPostModel.id] ではなく、いいねレコードの
/// [id] を使うこと。** `post.id` を使うとページングが壊れる。
class GalleryLikeModel {
  final String id;
  final GalleryPostModel post;

  const GalleryLikeModel({required this.id, required this.post});

  factory GalleryLikeModel.fromJson(
    Map<String, dynamic> json, {
    String host = '',
  }) {
    return GalleryLikeModel(
      id: json['id'] as String,
      post: GalleryPostModel.fromJson(
        json['post'] as Map<String, dynamic>,
        host: host,
      ),
    );
  }
}
