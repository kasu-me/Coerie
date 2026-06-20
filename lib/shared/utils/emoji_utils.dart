import 'package:flutter/widgets.dart';

/// 文字列が「絵文字一文字」（単一の書記素クラスタかつ絵文字を含む）かどうかを判定する。
/// 検索欄に絵文字そのものが入力されたケースを検出するために使用する。
bool isSingleEmoji(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  // 単一の書記素クラスタ（ZWJ シーケンスや肌色修飾を含む結合絵文字も1文字と数える）
  if (trimmed.characters.length != 1) return false;
  // 絵文字を構成するコードポイントが含まれているか確認する
  return trimmed.runes.any(_isEmojiRune);
}

/// コードポイントが絵文字（または絵文字構成要素）の範囲に含まれるか判定する。
bool _isEmojiRune(int r) {
  return (r >= 0x1F000 && r <= 0x1FAFF) || // 各種絵文字（絵文字・記号・乗り物等）
      (r >= 0x1F1E6 && r <= 0x1F1FF) || // 地域指標（国旗）
      (r >= 0x2600 && r <= 0x27BF) || // その他の記号・装飾記号
      (r >= 0x2300 && r <= 0x23FF) || // 技術記号（⌛⏰ 等）
      (r >= 0x2B00 && r <= 0x2BFF) || // 矢印・星等
      (r >= 0x2190 && r <= 0x21FF) || // 矢印
      r == 0x203C ||
      r == 0x2049 || // ‼ ⁉
      r == 0x20E3 || // キーキャップ結合文字
      r == 0x303D ||
      r == 0x3030 ||
      (r >= 0x3297 && r <= 0x3299); // ㊗ ㊙
}

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
  return 'https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.2/assets/72x72/$parts.png';
}
