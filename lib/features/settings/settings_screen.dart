import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../data/models/app_settings_model.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // --- テーマ設定 ---
          _SectionHeader('テーマ'),
          RadioGroup<String>(
            groupValue: settings.theme,
            onChanged: (v) => ref.read(settingsProvider.notifier).setTheme(v!),
            child: Column(
              children: const [
                RadioListTile<String>(
                  title: Text('システム設定に合わせる'),
                  value: 'system',
                ),
                RadioListTile<String>(title: Text('ライト'), value: 'light'),
                RadioListTile<String>(title: Text('ダーク'), value: 'dark'),
              ],
            ),
          ),

          // --- フォントサイズ ---
          _SectionHeader('フォントサイズ'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${settings.fontSize.toStringAsFixed(0)}pt'),
                Slider(
                  min: 10,
                  max: 22,
                  divisions: 12,
                  value: settings.fontSize,
                  label: settings.fontSize.toStringAsFixed(0),
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setFontSize(v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [Text('小'), Text('大')],
                ),
              ],
            ),
          ),

          // --- リアルタイム更新 ---
          _SectionHeader('タイムライン'),
          SwitchListTile(
            title: const Text('リアルタイム更新'),
            subtitle: const Text('WebSocketでタイムラインを自動更新する'),
            value: settings.realtimeUpdate,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setRealtimeUpdate(v),
          ),
          SwitchListTile(
            title: const Text('投稿日時を相対表示'),
            subtitle: Text(
              settings.dateTimeRelative ? '例: 3分前、2時間前' : '例: 2026/03/30 12:34',
            ),
            value: settings.dateTimeRelative,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setDateTimeRelative(v),
          ),
          if (!settings.dateTimeRelative)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('絶対時刻のタイムゾーン'),
              subtitle: Text(_timezoneLabel(settings.timezoneOffsetHours)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _pickTimezone(context, ref, settings.timezoneOffsetHours),
            ),

          // --- タブ設定 ---
          _SectionHeader('タブ'),
          ListTile(
            leading: const Icon(Icons.tab),
            title: const Text('タブの管理'),
            subtitle: Text('${settings.tabs.length}個のタブ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/tabs'),
          ),

          // --- 操作設定 ---
          _SectionHeader('操作'),
          SwitchListTile(
            title: const Text('破壊的操作の前に確認する'),
            subtitle: const Text('ノート削除・リノート解除などで確認ダイアログを表示する'),
            value: settings.confirmDestructive,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setConfirmDestructive(v),
          ),

          // --- 通知設定 ---
          _SectionHeader('通知'),
          SwitchListTile(
            title: const Text('プッシュ通知'),
            value: settings.notificationsEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setNotificationsEnabled(v),
          ),
          if (settings.notificationsEnabled) ...[
            SwitchListTile(
              title: const Text('返信'),
              value: settings.notifyReply,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyReply(v),
            ),
            SwitchListTile(
              title: const Text('フォロー'),
              value: settings.notifyFollow,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyFollow(v),
            ),
            SwitchListTile(
              title: const Text('リアクション'),
              value: settings.notifyReaction,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyReaction(v),
            ),
          ],

          // --- アカウント管理 ---
          _SectionHeader('アカウント'),
          ...accounts.map(
            (account) => ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(account.name),
              subtitle: Text(account.acct),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (account.isActive)
                    const Chip(
                      label: Text('使用中', style: TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRemoveAccount(
                      context,
                      ref,
                      account.id,
                      account.name,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('アカウントを追加'),
            onTap: () => context.push('/login'),
          ),

          // --- データ管理 ---
          _SectionHeader('データ管理'),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('設定をエクスポート'),
            subtitle: const Text('設定内容をJSONファイルとして保存'),
            onTap: () => _exportSettings(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('設定をインポート'),
            subtitle: const Text('JSONファイルから設定を復元'),
            onTap: () => _importSettings(context, ref),
          ),
        ],
      ),
    );
  }

  static const _tzOptions = [
    (label: 'デバイスの設定に従う', offset: null),
    (label: 'UTC-12 (IDLW)', offset: -12),
    (label: 'UTC-11 (SST)', offset: -11),
    (label: 'UTC-10 (HST)', offset: -10),
    (label: 'UTC-9 (AKST)', offset: -9),
    (label: 'UTC-8 (PST)', offset: -8),
    (label: 'UTC-7 (MST)', offset: -7),
    (label: 'UTC-6 (CST)', offset: -6),
    (label: 'UTC-5 (EST)', offset: -5),
    (label: 'UTC-4 (AST)', offset: -4),
    (label: 'UTC-3 (BRT)', offset: -3),
    (label: 'UTC+0 (UTC/GMT)', offset: 0),
    (label: 'UTC+1 (CET)', offset: 1),
    (label: 'UTC+2 (EET)', offset: 2),
    (label: 'UTC+3 (MSK)', offset: 3),
    (label: 'UTC+4 (GST)', offset: 4),
    (label: 'UTC+5 (PKT)', offset: 5),
    (label: 'UTC+6 (BST)', offset: 6),
    (label: 'UTC+7 (WIB)', offset: 7),
    (label: 'UTC+8 (CST/HKT)', offset: 8),
    (label: 'UTC+9 (JST/KST)', offset: 9),
    (label: 'UTC+10 (AEST)', offset: 10),
    (label: 'UTC+11 (AEDT)', offset: 11),
    (label: 'UTC+12 (NZST)', offset: 12),
  ];

  static String _timezoneLabel(int? offset) {
    if (offset == null) return 'デバイスの設定に従う';
    final match = _tzOptions.where((o) => o.offset == offset).firstOrNull;
    if (match != null) return match.label;
    return offset >= 0 ? 'UTC+$offset' : 'UTC$offset';
  }

  Future<void> _pickTimezone(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final selected = await showDialog<({String label, int? offset})>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('タイムゾーンを選択'),
        children: _tzOptions.map((opt) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, opt),
            child: Text(
              opt.label,
              style: TextStyle(
                fontWeight: opt.offset == current
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      ref
          .read(settingsProvider.notifier)
          .setTimezoneOffsetHours(selected.offset);
    }
  }

  Future<void> _exportSettings(
    BuildContext context,
    AppSettingsModel settings,
  ) async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final defaultName = 'coerie_settings_$timestamp.json';
    final jsonStr = settings.toJsonString();
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonStr));

    try {
      // bytes にデータを渡すことで file_picker が SAF 経由で書き込む（Android対応）
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '設定のエクスポート先を選択',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: jsonBytes,
      );

      if (savePath == null) return; // キャンセル

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存しました: $savePath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エクスポートに失敗しました: $e')));
      }
    }
  }

  Future<void> _importSettings(BuildContext context, WidgetRef ref) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ファイル選択に失敗しました: $e')));
      }
      return;
    }

    // キャンセル
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    final path = result.files.first.path;
    String jsonStr;
    try {
      if (bytes != null) {
        jsonStr = String.fromCharCodes(bytes);
      } else if (path != null) {
        jsonStr = await File(path).readAsString();
      } else {
        throw const FormatException('ファイルを読み込めませんでした');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ファイルの読み込みに失敗しました: $e')));
      }
      return;
    }

    try {
      final imported = AppSettingsModel.fromJsonString(jsonStr);
      await ref.read(settingsProvider.notifier).importSettings(imported);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('設定をインポートしました')));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('無効なJSONです: ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
      }
    }
  }

  Future<void> _confirmRemoveAccount(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('アカウントを削除'),
            content: Text('$name をアプリから削除しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('削除'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      ref.read(accountProvider.notifier).removeAccount(id);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
