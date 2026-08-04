/// インスタンスのカスタム絵文字（emojis エンドポイントの要素）。
class CustomEmojiModel {
  final String name;
  final String? url;

  /// 絵文字ピッカーでの分類。未分類の絵文字では空文字。
  final String category;

  /// 検索用の別名。
  final List<String> aliases;

  /// ローカル限定の絵文字。リモート投稿へのリアクションには使えない。
  final bool localOnly;

  const CustomEmojiModel({
    required this.name,
    this.url,
    this.category = '',
    this.aliases = const [],
    this.localOnly = false,
  });

  factory CustomEmojiModel.fromJson(Map<String, dynamic> json) {
    return CustomEmojiModel(
      name: json['name'] as String? ?? '',
      url: json['url'] as String?,
      category: (json['category'] as String?)?.trim() ?? '',
      aliases:
          (json['aliases'] as List<dynamic>?)
              ?.map((a) => a.toString())
              .toList() ??
          const [],
      localOnly: json['localOnly'] as bool? ?? false,
    );
  }
}
