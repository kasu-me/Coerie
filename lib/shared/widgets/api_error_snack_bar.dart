import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/api_error_message.dart';

/// API エラーを SnackBar で表示する。
///
/// 権限スコープ不足（[isPermissionError]）の場合は「再認証」アクションを添え、
/// アカウント設定画面へ誘導する。アクセストークンの権限は認証時に確定するため、
/// アプリ側で権限を追加しても既存ユーザーは再認証しないと新しい API を使えない。
///
/// [fallback] は判別できないエラーに使う既定メッセージ（例: `'投稿に失敗しました'`）。
void showApiErrorSnackBar(
  BuildContext context,
  Object error, {
  required String fallback,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final needsReauth = isPermissionError(error);
  // アクション実行時には元の画面が破棄されている可能性があるため、
  // context をクロージャに持ち込まず GoRouter を先に取り出しておく。
  final router = GoRouter.of(context);

  messenger.showSnackBar(
    SnackBar(
      content: Text(apiErrorMessage(error, fallback: fallback)),
      duration: needsReauth
          ? const Duration(seconds: 8)
          : const Duration(seconds: 4),
      action: needsReauth
          ? SnackBarAction(
              label: '再認証',
              onPressed: () => router.push('/account-settings'),
            )
          : null,
    ),
  );
}
