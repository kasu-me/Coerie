import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Misskey の公開範囲に対応するアイコン。
///
/// 同じ switch が note_card（通常・リノート）・compose・draft の4箇所に
/// 散っており、公開範囲を1つ増やすたびに全部直す必要があった。
/// 文言（[AppConstants.visibilityLabels]）と対にして扱うこと。
///
/// 未知の値は「全体公開」に倒す。サーバーがアプリの知らない公開範囲を
/// 返しても表示が壊れないようにするための既定値。
IconData visibilityIcon(String visibility) => switch (visibility) {
  AppConstants.visibilityPublic => Icons.public,
  AppConstants.visibilityHome => Icons.home_outlined,
  AppConstants.visibilityFollowers => Icons.lock_outline,
  AppConstants.visibilitySpecified => Icons.mail_outline,
  _ => Icons.public,
};
