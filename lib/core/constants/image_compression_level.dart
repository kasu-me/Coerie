/// 画像圧縮レベルの定義
enum ImageCompressionLevel {
  /// 無圧縮（そのままアップロード）
  none,

  /// 低圧縮（最大幅/高さ: 2000px, JPEG品質: 80%）
  low,

  /// 中圧縮（最大幅/高さ: 1500px, JPEG品質: 80%）
  medium,

  /// 高圧縮（最大幅/高さ: 1125px, JPEG品質: 80%）
  high;

  String get label {
    return switch (this) {
      ImageCompressionLevel.none => '無圧縮',
      ImageCompressionLevel.low => '低',
      ImageCompressionLevel.medium => '中',
      ImageCompressionLevel.high => '高',
    };
  }

  /// 最大幅・高さ（px）。null の場合は制限なし
  int? get maxDimension {
    return switch (this) {
      ImageCompressionLevel.none => null,
      ImageCompressionLevel.low => 2000,
      ImageCompressionLevel.medium => 1500,
      ImageCompressionLevel.high => 1125,
    };
  }

  /// JPEG品質（0〜100）。null の場合は変換しない
  int? get quality {
    return switch (this) {
      ImageCompressionLevel.none => null,
      ImageCompressionLevel.low => 80,
      ImageCompressionLevel.medium => 80,
      ImageCompressionLevel.high => 80,
    };
  }
}
