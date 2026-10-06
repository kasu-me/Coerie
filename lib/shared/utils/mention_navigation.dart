import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/misskey_api_provider.dart';

/// MFM 中のメンションをタップしたときに、そのユーザーのプロフィールへ遷移する。
///
/// メンションには username / host しか含まれず、プロフィール画面のルートは
/// ユーザーIDで引くため、遷移前に API でユーザーを解決する必要がある。
Future<void> openMentionedUser(
  BuildContext context,
  WidgetRef ref,
  String username,
  String? host,
) async {
  final api = ref.read(misskeyApiProvider);
  if (api == null) return;
  try {
    final user = await api.getUserByUsername(username, userHost: host);
    if (context.mounted) context.push('/profile/${user.id}');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ユーザーが見つかりませんでした: @$username')));
    }
  }
}
