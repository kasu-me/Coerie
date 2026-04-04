import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通知タブが表示されているかどうかを保持するプロバイダ。
/// family の key は accountId。
final notificationsTabVisibilityProvider = StateProvider.family<bool, String>(
  (ref, accountId) => false,
);
