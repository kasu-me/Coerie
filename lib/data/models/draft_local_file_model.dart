import '../../core/constants/image_compression_level.dart';

/// 下書きに保存された「まだアップロードしていない端末内のファイル」。
///
/// 実体はコピーせずパスだけを保持する。下書きのために数十MBの複製を抱える
/// コストの方が重いと判断したため。ただしピッカーが返すパスはアプリのキャッシュ
/// 領域を指すことがあり（image_picker / file_picker）、OSのキャッシュ削除で
/// 消えうる。そのため下書きを開くときに必ず実体の有無を確認し、無ければその添付を
/// 下書きから取り除くこと（`DraftNotifier.pruneMissingLocalFiles`）。
///
/// [toJson] / [fromJson] の結果が Hive に永続化されるため、フィールドを増やす
/// ときは必ず既定値を持たせること（旧レコードには値が存在しない）。
class DraftLocalFileModel {
  final String path;

  /// 投稿時に適用する圧縮レベル。圧縮後のファイルではなく設定値だけを保存する
  /// ため、下書きを開き直した後でもレベルを変更できる。
  final ImageCompressionLevel compressionLevel;

  final bool isSensitive;

  /// 保存時の添付一覧（Drive のファイルとローカルファイルの混在）における位置。
  /// これが無いと復元時に「Drive のファイルが先、ローカルが後」に並び替わり、
  /// ユーザーが並べた順序が壊れる。負値は位置不明として末尾に置く。
  final int position;

  const DraftLocalFileModel({
    required this.path,
    this.compressionLevel = ImageCompressionLevel.none,
    this.isSensitive = false,
    this.position = -1,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'compressionLevel': compressionLevel.name,
    'isSensitive': isSensitive,
    'position': position,
  };

  factory DraftLocalFileModel.fromJson(Map<String, dynamic> json) {
    final levelName = json['compressionLevel'] as String?;
    return DraftLocalFileModel(
      path: json['path'] as String,
      compressionLevel: ImageCompressionLevel.values.firstWhere(
        (l) => l.name == levelName,
        orElse: () => ImageCompressionLevel.none,
      ),
      isSensitive: json['isSensitive'] as bool? ?? false,
      position: json['position'] as int? ?? -1,
    );
  }
}
