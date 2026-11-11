import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/cache_service.dart';
import '../../data/models/avatar_decoration_model.dart';
import '../providers/settings_provider.dart';

/// ユーザーのアバター画像。URL が無い場合は人型アイコンを表示する。
class UserAvatar extends ConsumerWidget {
  final String? avatarUrl;

  /// 半径。null なら [CircleAvatar] の既定値。
  final double? radius;

  /// 代替アイコンの大きさ。null なら [IconTheme] の既定値。
  final double? iconSize;

  /// true のとき foregroundImage を使い、読み込み中・失敗時に代替アイコンを見せる。
  /// false（既定）は backgroundImage で、読み込めない場合は背景色のみになる。
  final bool foreground;

  /// 代替アイコン。既定は人型アイコン。
  final IconData icon;

  /// 代替アイコンの色。null なら指定なし。
  final Color? iconColor;

  /// [CircleAvatar] の背景色。null なら指定なし。
  final Color? backgroundColor;

  /// 重ねて描くアイコンデコレーション。
  ///
  /// アイコンの2倍の大きさで外側へはみ出し、レイアウト上の大きさには含めない。
  /// そのため半径12以下の小さなアイコンでは隣の文字を覆ってしまう。
  /// そうした箇所では渡さないこと。
  final List<AvatarDecorationModel> decorations;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius,
    this.iconSize,
    this.foreground = false,
    this.icon = Icons.person,
    this.iconColor,
    this.backgroundColor,
    this.decorations = const [],
  });

  /// [CircleAvatar] の radius 未指定時の既定値。
  static const double _defaultRadius = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = _buildAvatar();
    if (decorations.isEmpty) return avatar;

    final show = ref.watch(
      settingsProvider.select((s) => s.showAvatarDecorations),
    );
    if (!show) return avatar;

    final r = radius ?? _defaultRadius;
    final size = r * 4;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        for (final d in decorations)
          // Misskey Web と同じく、アイコンの2倍の大きさで中心を揃えて重ねる。
          Positioned(
            left: -r,
            top: -r,
            width: size,
            height: size,
            // はみ出した部分が隣のボタン等のタップを奪わないようにする。
            child: IgnorePointer(child: _DecorationImage(d, size: size)),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    final url = avatarUrl;
    final image = url != null
        ? CachedNetworkImageProvider(url, cacheManager: AppCacheManager())
        : null;

    if (image != null && !foreground) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: image,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage: image,
      child: Icon(icon, size: iconSize, color: iconColor),
    );
  }
}

class _DecorationImage extends StatelessWidget {
  final AvatarDecorationModel decoration;
  final double size;

  const _DecorationImage(this.decoration, {required this.size});

  @override
  Widget build(BuildContext context) {
    final d = decoration;
    // Misskey Web は CSS の translate / rotate / scale 個別プロパティで指定しており、
    // その合成順（translate → rotate → scale、中心基準）に合わせている。
    // translate の % はデコレーション画像自身の大きさに対する割合。
    final transform = Matrix4.translationValues(
      d.offsetX * size,
      d.offsetY * size,
      0,
    )..rotateZ(d.angle * 2 * math.pi);
    if (d.flipH) transform.multiply(Matrix4.diagonal3Values(-1, 1, 1));

    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: CachedNetworkImage(
        imageUrl: d.url,
        cacheManager: AppCacheManager(),
        width: size,
        height: size,
        // CSS では width: 200% / height: auto のため、縦横比を保って上端に揃える。
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        fadeInDuration: Duration.zero,
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
