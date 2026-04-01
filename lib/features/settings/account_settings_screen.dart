import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/account_provider.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('アカウント設定')),
      body: ListView(
        children: [
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
