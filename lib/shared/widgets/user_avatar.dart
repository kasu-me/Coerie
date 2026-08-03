import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/services/cache_service.dart';

/// ユーザーのアバター画像。URL が無い場合は人型アイコンを表示する。
class UserAvatar extends StatelessWidget {
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

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius,
    this.iconSize,
    this.foreground = false,
    this.icon = Icons.person,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
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
