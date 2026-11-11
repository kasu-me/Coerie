/// ユーザーのアイコンデコレーション（UserLite の `avatarDecorations` の要素）。
class AvatarDecorationModel {
  final String id;
  final String url;

  /// 回転量。1.0 で一回転（Misskey Web は `angle * 360deg` で回す）。
  final double angle;

  /// 左右反転するか。
  final bool flipH;

  /// デコレーション画像自身の大きさに対する割合での移動量。
  final double offsetX;
  final double offsetY;

  const AvatarDecorationModel({
    required this.id,
    required this.url,
    this.angle = 0,
    this.flipH = false,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  factory AvatarDecorationModel.fromJson(Map<String, dynamic> json) =>
      AvatarDecorationModel(
        id: json['id'] as String,
        url: json['url'] as String,
        angle: (json['angle'] as num?)?.toDouble() ?? 0,
        flipH: json['flipH'] as bool? ?? false,
        offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
        offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
      );
}

/// `avatarDecorations` を変換する。
/// 対応前のサーバー（Misskey 2023.11 より前や他の実装）はフィールド自体を返さないため、
/// 欠落・不正な要素は黙って捨てる。
List<AvatarDecorationModel> parseAvatarDecorations(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map<String, dynamic> && e['id'] is String && e['url'] is String)
        AvatarDecorationModel.fromJson(e),
  ];
}
