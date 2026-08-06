import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/app_settings_model.dart';
import '../providers/account_provider.dart';
import '../providers/account_tabs_provider.dart';

/// 「ホームタブに追加」ダイアログを出し、確定されたらタブを追加する。
///
/// リスト・アンテナ・チャンネル・ルーター内タイムラインの4箇所に同じ処理が
/// 複製されており、うち3箇所は [TextEditingController] を破棄し忘れていた。
///
/// [defaultLabel] はダイアログの初期値。入力が空なら [defaultLabel] を使う。
/// 追加に成功したら true を返す（呼び出し側で状態更新したい場合に使う）。
Future<bool> addToHomeTab(
  BuildContext context,
  WidgetRef ref, {
  required String tabType,
  required String sourceId,
  required String defaultLabel,
}) async {
  final labelController = TextEditingController(text: defaultLabel);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ホームタブに追加'),
      content: TextField(
        controller: labelController,
        decoration: const InputDecoration(
          labelText: 'タブ名',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('追加'),
        ),
      ],
    ),
  );
  final input = labelController.text.trim();
  labelController.dispose();
  if (confirmed != true || !context.mounted) return false;

  final label = input.isEmpty ? defaultLabel : input;
  final accountId = ref.read(activeAccountProvider)?.id ?? '';
  final currentTabs = List<TabConfigModel>.from(
    ref.read(accountTabsProvider(accountId)),
  );
  currentTabs.add(
    TabConfigModel(
      id: const Uuid().v4(),
      label: label,
      type: tabType,
      sourceId: sourceId,
    ),
  );
  await ref.read(accountTabsProvider(accountId).notifier).setTabs(currentTabs);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('「$label」タブを追加しました')));
  }
  return true;
}
