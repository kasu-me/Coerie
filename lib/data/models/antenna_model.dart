/// Misskey のアンテナ（antennas/*）。
class AntennaModel {
  final String id;
  final String name;

  /// 受信範囲。`all` / `home` / `users` / `list` / `users_blacklist` のいずれか。
  final String src;

  /// 受信キーワード。外側の配列が OR、内側が AND を表す。
  final List<List<String>> keywords;

  /// 除外キーワード。[keywords] と同じ構造。
  final List<List<String>> excludeKeywords;

  /// 対象ユーザーの acct 文字列（`"@username@host"`）。
  /// アンテナ API は id を返さないため、ユーザーは acct でしか特定できない。
  final List<String> users;

  /// `src` が `list` のときの対象リスト。
  final String? userListId;

  final bool caseSensitive;
  final bool withReplies;
  final bool withFile;
  final bool localOnly;
  final bool excludeBots;
  final bool excludeNotesInSensitiveChannel;

  const AntennaModel({
    required this.id,
    required this.name,
    this.src = 'all',
    this.keywords = const [],
    this.excludeKeywords = const [],
    this.users = const [],
    this.userListId,
    this.caseSensitive = false,
    this.withReplies = false,
    this.withFile = false,
    this.localOnly = false,
    this.excludeBots = false,
    this.excludeNotesInSensitiveChannel = false,
  });

  factory AntennaModel.fromJson(Map<String, dynamic> json) {
    return AntennaModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      src: json['src'] as String? ?? 'all',
      keywords: _toKeywordRows(json['keywords']),
      excludeKeywords: _toKeywordRows(json['excludeKeywords']),
      users:
          (json['users'] as List<dynamic>?)
              ?.map((u) => u.toString())
              .toList() ??
          const [],
      userListId: json['userListId'] as String?,
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      withReplies: json['withReplies'] as bool? ?? false,
      withFile: json['withFile'] as bool? ?? false,
      localOnly: json['localOnly'] as bool? ?? false,
      excludeBots: json['excludeBots'] as bool? ?? false,
      excludeNotesInSensitiveChannel:
          json['excludeNotesInSensitiveChannel'] as bool? ?? false,
    );
  }

  static List<List<String>> _toKeywordRows(dynamic raw) {
    final rows = raw as List<dynamic>?;
    if (rows == null) return const [];
    return rows
        .map((row) => (row as List<dynamic>).map((w) => w.toString()).toList())
        .toList();
  }
}
