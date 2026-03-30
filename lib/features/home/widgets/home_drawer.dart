import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../data/models/account_model.dart';

class HomeDrawer extends ConsumerWidget {
  const HomeDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider);
    final activeAccount = ref.watch(activeAccountProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(
              account: activeAccount,
              accounts: accounts,
              ref: ref,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('ドライブ'),
              onTap: () {
                Navigator.of(context).pop();
                // TODO: ドライブ画面へ遷移
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('下書き'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/drafts');
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('アプリ設定'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AccountModel? account;
  final List<AccountModel> accounts;
  final WidgetRef ref;

  const _ProfileHeader({
    required this.account,
    required this.accounts,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (account == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('ログインしていません'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/profile/${account!.userId}');
                },
                child: account!.avatarUrl != null
                    ? CircleAvatar(
                        radius: 28,
                        backgroundImage: CachedNetworkImageProvider(
                          account!.avatarUrl!,
                        ),
                      )
                    : const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.person, size: 28),
                      ),
              ),
              const Spacer(),
              if (accounts.length > 1)
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'アカウント切り替え',
                  onPressed: () => _showAccountSwitcher(context),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              context.push('/profile/${account!.userId}');
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account!.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  account!.acct,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'アカウント切り替え',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...accounts.map(
            (a) => ListTile(
              leading: a.avatarUrl != null
                  ? CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(a.avatarUrl!),
                    )
                  : const CircleAvatar(child: Icon(Icons.person)),
              title: Text(a.name),
              subtitle: Text(a.acct),
              trailing: a.isActive
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                ref.read(accountProvider.notifier).switchAccount(a.id);
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
            ),
          ),          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('アカウントを追加'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              context.push('/login');
            },
          ),        ],
      ),
    );
  }
}
