import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'misskey_api_provider.dart';
import '../../data/models/user_model.dart';

/// 現在ログイン中のユーザー情報を提供するプロバイダー。
/// アカウントが切り替わると自動的に再取得される。
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return null;
  try {
    return await api.getMe();
  } catch (_) {
    return null;
  }
});
