import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../constants/image_compression_level.dart';

/// JPEG/PNG 画像の圧縮を担うサービス
class ImageCompressionService {
  const ImageCompressionService._();

  /// [level] が [ImageCompressionLevel.none] の場合は元ファイルをそのまま返す。
  /// 対象外の拡張子（jpeg/jpg/png 以外）の場合も元ファイルをそのまま返す。
  /// 圧縮後は一時ファイルに書き出し、その [File] を返す。
  static Future<File> compress({
    required File file,
    required ImageCompressionLevel level,
  }) async {
    if (level == ImageCompressionLevel.none) return file;

    final ext = p.extension(file.path).toLowerCase();
    if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') return file;

    final CompressFormat format = (ext == '.png')
        ? CompressFormat.png
        : CompressFormat.jpeg;

    final tmpDir = await getTemporaryDirectory();
    final outPath = p.join(
      tmpDir.path,
      'compressed_${DateTime.now().millisecondsSinceEpoch}$ext',
    );

    // PNG の quality パラメーターは iOS では無視される
    final quality = level.quality ?? 80;
    final maxDim = level.maxDimension ?? 4096;

    // minWidth/minHeight に最大解像度を指定すると、
    // scale = max(1, min(srcW/minW, srcH/minH)) で縮小率が計算される。
    // 両辺が maxDim 以下の場合は scale=1 でリサイズされない。
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      outPath,
      format: format,
      quality: quality,
      minWidth: maxDim,
      minHeight: maxDim,
    );

    return result != null ? File(result.path) : file;
  }

  /// 対象ファイルが圧縮可能な形式（jpeg/jpg/png）かどうかを返す
  static bool isCompressible(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png';
  }
}
