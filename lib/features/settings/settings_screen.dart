import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/account_visibility_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../data/models/account_model.dart';
import '../../data/models/app_settings_model.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // --- 外観 ---
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外観'),
            subtitle: const Text('テーマ・フォントサイズ・アイコンサイズ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/appearance'),
          ),
          const Divider(indent: 16, endIndent: 16),

          // --- タイムライン表示 ---
          ListTile(
            leading: const Icon(Icons.view_list_outlined),
            title: const Text('タイムライン表示'),
            subtitle: const Text('リアルタイム更新・投稿日時・アニメーションなど'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/timeline'),
          ),
          const Divider(indent: 16, endIndent: 16),

          // --- 画像投稿 ---
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('画像投稿'),
            subtitle: const Text('デフォルト圧縮率'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/image-posting'),
          ),
          const Divider(indent: 16, endIndent: 16),

          // --- タブ ---
          Consumer(
            builder: (context, ref, _) {
              final accountId = ref.watch(activeAccountProvider)?.id ?? '';
              final tabs = ref.watch(accountTabsProvider(accountId));
              return ListTile(
                leading: const Icon(Icons.tab_outlined),
                title: const Text('タブ管理'),
                subtitle: Text('${tabs.length}個のタブ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/tabs'),
              );
            },
          ),
          const Divider(indent: 16, endIndent: 16),

          // --- 通知 ---
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知'),
            subtitle: Text(
              settings.notificationsEnabled ? 'プッシュ通知: オン' : 'プッシュ通知: オフ',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/notifications'),
          ),
          const Divider(indent: 16, endIndent: 16),

          // --- 操作 ---
          _SectionHeader('操作'),
          SwitchListTile(
            secondary: const Icon(Icons.warning_amber_outlined),
            title: const Text('破壊的操作の前に確認する'),
            subtitle: const Text('ノート削除・リノート解除などで確認ダイアログを表示する'),
            value: settings.confirmDestructive,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setConfirmDestructive(v),
          ),

          // --- データ管理 ---
          _SectionHeader('データ管理'),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('設定をエクスポート'),
            subtitle: const Text('設定内容をJSONファイルとして保存'),
            onTap: () => _exportSettings(context, ref, settings),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('設定をエクスポート（アクセストークンを含む）'),
            subtitle: const Text('アクセストークンを含む設定内容をJSONファイルとして保存'),
            onTap: () => _exportSettingsWithToken(context, ref, settings),
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

  Future<void> _exportSettingsWithToken(
    BuildContext context,
    WidgetRef ref,
    AppSettingsModel settings,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('セキュリティに関する警告'),
        content: const Text(
          'この操作にはアクセストークンの書き出しが含まれます。\n\n'
          'アクセストークンが第三者に渡ると、あなたのアカウントが不正に操作される可能性があります。'
          '保存したファイルの取り扱いには十分に注意してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('同意してエクスポート'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final defaultName = 'coerie_settings_with_tokens_$timestamp.json';

    final accounts = ref.read(accountProvider);
    final accountSettings = <String, dynamic>{};
    for (final account in accounts) {
      accountSettings[account.id] = {
        'tabs': ref
            .read(accountTabsProvider(account.id))
            .map((t) => t.toJson())
            .toList(),
        'defaultVisibility': ref.read(accountVisibilityProvider(account.id)),
      };
    }

    // バージョン3フォーマット: globalSettings + accountSettings + accounts（トークン含む）
    final exportData = {
      'version': 3,
      'globalSettings': settings.toJson(),
      'accountSettings': accountSettings,
      'accounts': accounts.map((a) => a.toJson()).toList(),
    };
    final jsonStr = jsonEncode(exportData);
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonStr));

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '設定のエクスポート先を選択',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: jsonBytes,
      );

      if (savePath == null) return;

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

  Future<void> _exportSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettingsModel settings,
  ) async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final defaultName = 'coerie_settings_$timestamp.json';

    // アカウント別設定（タブ・公開範囲）をまとめる
    final accounts = ref.read(accountProvider);
    final accountSettings = <String, dynamic>{};
    for (final account in accounts) {
      accountSettings[account.id] = {
        'tabs': ref
            .read(accountTabsProvider(account.id))
            .map((t) => t.toJson())
            .toList(),
        'defaultVisibility': ref.read(accountVisibilityProvider(account.id)),
      };
    }

    // バージョン2フォーマット: globalSettings + accountSettings
    final exportData = {
      'version': 2,
      'globalSettings': settings.toJson(),
      'accountSettings': accountSettings,
    };
    final jsonStr = jsonEncode(exportData);
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonStr));

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '設定のエクスポート先を選択',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: jsonBytes,
      );

      if (savePath == null) return;

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

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    final path = result.files.first.path;
    String jsonStr;
    try {
      if (bytes != null) {
        jsonStr = utf8.decode(bytes);
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
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = decoded['version'] as int? ?? 1;

      if (version >= 2) {
        // バージョン2: globalSettings + accountSettings
        final globalJson =
            decoded['globalSettings'] as Map<String, dynamic>? ?? decoded;
        final imported = AppSettingsModel.fromJson(globalJson);
        await ref.read(settingsProvider.notifier).importSettings(imported);

        final accountSettingsMap =
            decoded['accountSettings'] as Map<String, dynamic>? ?? {};
        for (final entry in accountSettingsMap.entries) {
          final accountId = entry.key;
          final data = entry.value as Map<String, dynamic>;

          final tabsJson = data['tabs'] as List<dynamic>?;
          if (tabsJson != null) {
            final tabs = tabsJson
                .map((e) => TabConfigModel.fromJson(e as Map<String, dynamic>))
                .toList();
            await ref
                .read(accountTabsProvider(accountId).notifier)
                .setTabs(tabs);
          }

          final visibility = data['defaultVisibility'] as String?;
          if (visibility != null) {
            await ref
                .read(accountVisibilityProvider(accountId).notifier)
                .setVisibility(visibility);
          }
        }

        // バージョン3: アカウント情報（トークン含む）を復元
        if (version >= 3) {
          final accountsJson = decoded['accounts'] as List<dynamic>?;
          if (accountsJson != null) {
            final importedAccounts = accountsJson
                .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
                .toList();
            await ref
                .read(accountProvider.notifier)
                .importAccounts(importedAccounts);
          }
        }
      } else {
        // バージョン1（旧フォーマット）: AppSettingsModelのみ
        final imported = AppSettingsModel.fromJson(decoded);
        await ref.read(settingsProvider.notifier).importSettings(imported);

        // 旧フォーマットのtabsを現在のアクティブアカウントに適用
        if (imported.tabs.isNotEmpty) {
          final accountId = ref.read(activeAccountProvider)?.id ?? '';
          if (accountId.isNotEmpty) {
            await ref
                .read(accountTabsProvider(accountId).notifier)
                .setTabs(imported.tabs);
          }
        }
      }

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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
