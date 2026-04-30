/// Twemoji CDN の URL を返す。
/// U+FE0F (バリエーションセレクタ-16) はキーキャップシーケンス以外では
/// Twemoji のファイル名に含まれないため除外する。
String twemojiUrl(String emoji) {
  final runes = emoji.runes.toList();
  final filtered = <int>[];
  for (int i = 0; i < runes.length; i++) {
    if (runes[i] == 0xFE0F) {
      // キーキャップシーケンス（FE0F の直後が U+20E3）の場合のみ FE0F を保持
      if (i + 1 < runes.length && runes[i + 1] == 0x20E3) {
        filtered.add(runes[i]);
      }
      // それ以外のバリエーションセレクタ-16 は Twemoji ファイル名に含まれないため除外
    } else {
      filtered.add(runes[i]);
    }
  }
  final parts = filtered.map((r) => r.toRadixString(16)).join('-');
  return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$parts.png';
}
