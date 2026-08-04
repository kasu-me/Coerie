import 'drive_file_model.dart';
import 'user_model.dart';

/// ページ本文を構成するブロック。
///
/// 現行 Misskey（v2026.6.0）の `packedPageBlockSchema` は
/// `text` / `section` / `image` / `note` の4種類のみ。
/// AiScript ベースの動的ブロック（button / if / counter 等）は廃止済みだが、
/// 古いページには残っている可能性があるため、未知の type は
/// [PageUnknownBlock] として元 JSON ごと保持する。
///
/// 全ブロックは元の JSON を [raw] に保持しており、[toJson] で
/// 元フィールドをマージして返す。これにより本アプリが解釈しない
/// フィールドが編集の往復で失われない。
sealed class PageBlock {
  final String id;
  final String type;

  /// サーバーから受け取った元の JSON。往復で情報を落とさないために保持する。
  final Map<String, dynamic> raw;

  const PageBlock({
    required this.id,
    required this.type,
    this.raw = const {},
  });

  factory PageBlock.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final type = json['type'] as String? ?? '';
    switch (type) {
      case 'text':
        return PageTextBlock(
          id: id,
          text: json['text'] as String? ?? '',
          raw: json,
        );
      case 'section':
        return PageSectionBlock(
          id: id,
          title: json['title'] as String? ?? '',
          children: PageBlock.listFromJson(json['children']),
          raw: json,
        );
      case 'image':
        return PageImageBlock(
          id: id,
          fileId: json['fileId'] as String?,
          raw: json,
        );
      case 'note':
        return PageNoteBlock(
          id: id,
          noteId: json['note'] as String?,
          detailed: json['detailed'] as bool? ?? false,
          raw: json,
        );
      default:
        return PageUnknownBlock(id: id, type: type, raw: json);
    }
  }

  /// ブロック配列（`content` / `children`）をパースする。
  static List<PageBlock> listFromJson(dynamic json) {
    if (json is! List) return const [];
    return json
        .whereType<Map<String, dynamic>>()
        .map(PageBlock.fromJson)
        .toList();
  }

  Map<String, dynamic> toJson();

  /// 元 JSON に本アプリが扱うフィールドを上書きした Map を作る。
  Map<String, dynamic> mergedJson(Map<String, dynamic> fields) => {
    ...raw,
    'id': id,
    'type': type,
    ...fields,
  };
}

/// MFM テキストブロック。
class PageTextBlock extends PageBlock {
  final String text;

  const PageTextBlock({
    required super.id,
    required this.text,
    super.raw,
  }) : super(type: 'text');

  PageTextBlock copyWith({String? text}) =>
      PageTextBlock(id: id, text: text ?? this.text, raw: raw);

  @override
  Map<String, dynamic> toJson() => mergedJson({'text': text});
}

/// 見出しブロック。[children] にブロックを再帰的に入れ子にできる。
class PageSectionBlock extends PageBlock {
  final String title;
  final List<PageBlock> children;

  const PageSectionBlock({
    required super.id,
    required this.title,
    this.children = const [],
    super.raw,
  }) : super(type: 'section');

  PageSectionBlock copyWith({String? title, List<PageBlock>? children}) =>
      PageSectionBlock(
        id: id,
        title: title ?? this.title,
        children: children ?? this.children,
        raw: raw,
      );

  @override
  Map<String, dynamic> toJson() => mergedJson({
    'title': title,
    'children': children.map((c) => c.toJson()).toList(),
  });
}

/// 画像ブロック。[fileId] しか持たないため、実際の URL は
/// [PageModel.attachedFiles]（[PageModel.fileById]）から解決する。
class PageImageBlock extends PageBlock {
  final String? fileId;

  const PageImageBlock({required super.id, this.fileId, super.raw})
    : super(type: 'image');

  PageImageBlock copyWith({String? fileId}) =>
      PageImageBlock(id: id, fileId: fileId ?? this.fileId, raw: raw);

  @override
  Map<String, dynamic> toJson() => mergedJson({'fileId': fileId});
}

/// ノート埋め込みブロック。noteId のみを持つため、表示には
/// `notes/show` の追加取得が必要（N+1 になるので遅延読み込み推奨）。
class PageNoteBlock extends PageBlock {
  /// 埋め込むノートの ID。JSON 上のキーは `note`。
  final String? noteId;
  final bool detailed;

  const PageNoteBlock({
    required super.id,
    this.noteId,
    this.detailed = false,
    super.raw,
  }) : super(type: 'note');

  PageNoteBlock copyWith({String? noteId, bool? detailed}) => PageNoteBlock(
    id: id,
    noteId: noteId ?? this.noteId,
    detailed: detailed ?? this.detailed,
    raw: raw,
  );

  @override
  Map<String, dynamic> toJson() =>
      mergedJson({'note': noteId, 'detailed': detailed});
}

/// 本アプリが解釈しないブロック。表示側では
/// 「このブロックは表示できません」のプレースホルダを出し、
/// 保存時は元 JSON をそのまま送り返す。
class PageUnknownBlock extends PageBlock {
  const PageUnknownBlock({
    required super.id,
    required super.type,
    super.raw,
  });

  @override
  Map<String, dynamic> toJson() => mergedJson(const {});
}

/// Misskey のページ（`https://host/@username/pages/<name>`）。
class PageModel {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;
  final UserModel? user;

  /// 表示タイトル。
  final String title;

  /// URL スラッグ。**同一ユーザー内でユニーク**（重複すると `NAME_ALREADY_EXISTS`）。
  final String name;
  final String? summary;

  /// `serif` または `sans-serif`。
  final String font;
  final bool alignCenter;
  final bool hideTitleWhenPinned;

  final String? eyeCatchingImageId;
  final DriveFileModel? eyeCatchingImage;

  /// 本文中の画像ブロックが参照するファイルの実体。
  final List<DriveFileModel> attachedFiles;

  final List<PageBlock> content;

  /// 廃止された AiScript 機能の名残。`pages/create` では必須フィールドのため、
  /// 空でも往復で保持して送り返す。
  final List<dynamic> variables;
  final String script;

  final int likedCount;

  /// 未認証時は API が返さないため null。
  final bool? isLiked;

  const PageModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.user,
    required this.title,
    required this.name,
    this.summary,
    this.font = 'sans-serif',
    this.alignCenter = false,
    this.hideTitleWhenPinned = false,
    this.eyeCatchingImageId,
    this.eyeCatchingImage,
    this.attachedFiles = const [],
    this.content = const [],
    this.variables = const [],
    this.script = '',
    this.likedCount = 0,
    this.isLiked,
  });

  /// 画像ブロックの `fileId` から DriveFile を引くためのマップ。
  /// 削除済みファイルは含まれないため、参照側でフォールバックが必要。
  Map<String, DriveFileModel> get fileById => {
    for (final f in attachedFiles) f.id: f,
    ?eyeCatchingImage?.id: ?eyeCatchingImage,
  };

  factory PageModel.fromJson(Map<String, dynamic> json, {String host = ''}) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final userJson = json['user'];
    final eyeCatchingImageJson = json['eyeCatchingImage'];
    return PageModel(
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
      name: json['name'] as String? ?? '',
      summary: json['summary'] as String?,
      font: json['font'] as String? ?? 'sans-serif',
      alignCenter: json['alignCenter'] as bool? ?? false,
      hideTitleWhenPinned: json['hideTitleWhenPinned'] as bool? ?? false,
      eyeCatchingImageId: json['eyeCatchingImageId'] as String?,
      eyeCatchingImage: eyeCatchingImageJson is Map<String, dynamic>
          ? DriveFileModel.fromJson(eyeCatchingImageJson)
          : null,
      attachedFiles:
          (json['attachedFiles'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(DriveFileModel.fromJson)
              .toList() ??
          const [],
      content: PageBlock.listFromJson(json['content']),
      variables: (json['variables'] as List<dynamic>?) ?? const [],
      script: json['script'] as String? ?? '',
      likedCount: json['likedCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool?,
    );
  }

  PageModel copyWith({
    String? title,
    String? name,
    String? summary,
    String? font,
    bool? alignCenter,
    bool? hideTitleWhenPinned,
    String? eyeCatchingImageId,
    DriveFileModel? eyeCatchingImage,
    List<DriveFileModel>? attachedFiles,
    List<PageBlock>? content,
    int? likedCount,
    bool? isLiked,
  }) {
    return PageModel(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      userId: userId,
      user: user,
      title: title ?? this.title,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      font: font ?? this.font,
      alignCenter: alignCenter ?? this.alignCenter,
      hideTitleWhenPinned: hideTitleWhenPinned ?? this.hideTitleWhenPinned,
      eyeCatchingImageId: eyeCatchingImageId ?? this.eyeCatchingImageId,
      eyeCatchingImage: eyeCatchingImage ?? this.eyeCatchingImage,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      content: content ?? this.content,
      variables: variables,
      script: script,
      likedCount: likedCount ?? this.likedCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

/// `i/page-likes` の戻り値のラッパー。
///
/// **ページングのカーソルには [PageModel.id] ではなく、いいねレコードの
/// [id] を使うこと。** `page.id` を使うとページングが壊れる。
class PageLikeModel {
  final String id;
  final PageModel page;

  const PageLikeModel({required this.id, required this.page});

  factory PageLikeModel.fromJson(
    Map<String, dynamic> json, {
    String host = '',
  }) {
    return PageLikeModel(
      id: json['id'] as String,
      page: PageModel.fromJson(
        json['page'] as Map<String, dynamic>,
        host: host,
      ),
    );
  }
}
