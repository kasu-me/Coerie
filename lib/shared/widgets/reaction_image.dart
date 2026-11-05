import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/services/cache_service.dart';

/// リアクション絵文字の画像。
///
/// 文字を画像にした横長のカスタム絵文字は、正方形に収めると読めないほど小さくなるため、
/// 高さを [size] に揃えて横へ伸ばす。
///
/// 親の最大幅を超える場合は、比率を保ったまま親の幅に収まるよう縮小される。
/// `Row` の非 Flex 子には幅の上限が渡らずはみ出すので、呼び出し側で
/// `Flexible` などにより上限を与えること。
class ReactionImage extends StatelessWidget {
  final String imageUrl;
  final double size;

  /// 読み込みに失敗したときに代わりに表示するウィジェット。
  final Widget fallback;

  const ReactionImage({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // 読み込み中は比率が分からない。正方形の枠を確保しておくことで、大半を占める
      // 正方形の絵文字では読み込み完了時にレイアウトがずれない。
      // 縦長の絵文字も同じ枠に収まり、横幅が絵文字ごとにばらつかない。
      constraints: BoxConstraints(minWidth: size),
      child: CachedNetworkImage(
        cacheManager: AppCacheManager(),
        imageUrl: imageUrl,
        height: size,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
