import 'package:flutter/painting.dart';

/// `#RRGGBB` / `#AARRGGBB` 形式の文字列を [Color] に変換する。
///
/// Misskey のチャンネルカラーなど、サーバーから任意の文字列が来る箇所で使う。
/// 解釈できない場合は null を返すので、呼び出し側でテーマ色などに退避すること。
Color? channelColorFromHex(String? hex) {
  if (hex == null) return null;
  final normalized = hex.replaceAll('#', '');
  final value = int.tryParse(
    normalized.length == 6 ? 'FF$normalized' : normalized,
    radix: 16,
  );
  return value == null ? null : Color(value);
}
