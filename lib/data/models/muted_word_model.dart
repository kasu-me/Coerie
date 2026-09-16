/// ワードミュートの1エントリ。
///
/// Misskey の `mutedWords` は「キーワードの配列（AND 条件）」と
/// 「`/pattern/flags` 形式の文字列（正規表現）」が混在した配列で返る。
/// `i/update` は全置換のため、片方の形に潰して保持すると、1件追加・削除する
/// だけで正規表現エントリがただのキーワードへ書き換わってしまう。
/// 読み書きの往復で壊さないよう、両方の形を区別して保持する。
class MutedWordModel {
  /// AND 条件のキーワード群。正規表現エントリでは空。
  final List<String> keywords;

  /// 正規表現エントリの生文字列（`/pattern/flags`）。キーワードエントリでは null。
  final String? regexSource;

  // late final の _regex を持つため const コンストラクタにはできない。
  MutedWordModel.keywords(this.keywords) : regexSource = null;

  MutedWordModel.regex(String this.regexSource) : keywords = const [];

  /// `/pattern/flags` 形式の判別に使う。Misskey 本家の `checkWordMute` と同じ形。
  static final RegExp _regexEntry = RegExp(r'^/(.+)/([a-z]*)$', dotAll: true);

  /// API の配列要素1つから生成する。解釈できない要素は null を返す。
  static MutedWordModel? fromJson(dynamic raw) {
    if (raw is List) {
      final keywords = raw
          .whereType<String>()
          .where((k) => k.isNotEmpty)
          .toList();
      return keywords.isEmpty ? null : MutedWordModel.keywords(keywords);
    }
    if (raw is String) {
      if (raw.isEmpty) return null;
      // 文字列要素は本来すべて正規表現だが、`/.../` 形式でないものは
      // 単一キーワードとして扱う（壊れた設定でもミュートを効かせるため）。
      return _regexEntry.hasMatch(raw)
          ? MutedWordModel.regex(raw)
          : MutedWordModel.keywords([raw]);
    }
    return null;
  }

  /// API へ送る形（正規表現は文字列、キーワードは配列）。
  dynamic toJson() => regexSource ?? keywords;

  bool get isRegex => regexSource != null;

  /// 設定画面での表示文字列。
  String get label => regexSource ?? keywords.join(' ');

  /// コンパイル済み正規表現。不正なパターンは null（=どのノートにも一致しない）。
  late final RegExp? _regex = _compile();

  RegExp? _compile() {
    final source = regexSource;
    if (source == null) return null;
    final m = _regexEntry.firstMatch(source);
    if (m == null) return null;
    final flags = m.group(2) ?? '';
    try {
      return RegExp(
        m.group(1)!,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        dotAll: flags.contains('s'),
      );
    } catch (_) {
      // 本家の入力チェックをすり抜けた不正パターン。判定不能なので一致させない。
      return null;
    }
  }

  /// [text]（CW + 本文）がこのエントリに一致するか。
  /// キーワードエントリは全語を含む場合のみ一致（AND 条件・大文字小文字は区別する）。
  bool matches(String text) {
    final regex = _regex;
    if (regex != null) return regex.hasMatch(text);
    if (keywords.isEmpty) return false;
    return keywords.every(text.contains);
  }
}

/// サーバーに保存されているワードミュート設定一式。
///
/// Misskey はソフト（`mutedWords`）とハード（`hardMutedWords`）を別フィールドで
/// 保持しており、本家の設定画面もそれぞれ別の欄になっている。片方だけを扱うと
/// 「本家で登録したのにアプリ側に出てこない」状態になるため、両方を持つ。
///
/// 本家での違いは表示方法（ソフトは折りたたみ、ハードは完全非表示）で、
/// Coerie はどちらも非表示にするため判定上は区別しない。
class WordMuteSettings {
  /// ソフトワードミュート（`mutedWords`）。
  final List<MutedWordModel> soft;

  /// ハードワードミュート（`hardMutedWords`）。
  final List<MutedWordModel> hard;

  const WordMuteSettings({this.soft = const [], this.hard = const []});

  static const WordMuteSettings empty = WordMuteSettings();

  /// 判定に使う全エントリ。
  List<MutedWordModel> get all => [...soft, ...hard];

  bool get isEmpty => soft.isEmpty && hard.isEmpty;
}
