import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

/// 破壊的操作の確認ダイアログを表示し、続行してよいかを返す。
///
/// 設定「破壊的操作の確認」がオフの場合はダイアログを出さず即座に true を返すため、
/// 呼び出し側で設定を読む必要はない。
///
/// [destructive] が true のとき確定ボタンをエラー色にする。
/// リノートのように取り消しが利く操作では false を指定する。
Future<bool> confirmAction(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'キャンセル',
  bool destructive = true,
}) async {
  if (!ref.read(settingsProvider).confirmDestructive) return true;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogCtx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
