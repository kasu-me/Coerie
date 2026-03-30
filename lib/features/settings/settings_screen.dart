import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/account_provider.dart';

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

          // --- タブ設定 ---
          _SectionHeader('タブ'),
          ListTile(
            leading: const Icon(Icons.tab),
            title: const Text('タブの管理'),
            subtitle: Text('${settings.tabs.length}個のタブ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/tabs'),
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
        ],
      ),
    );
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
