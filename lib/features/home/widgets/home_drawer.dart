import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../data/models/account_model.dart';
import '../../../shared/providers/follow_requests_badge_provider.dart';
import '../../../shared/providers/announcements_badge_provider.dart';
import '../../profile/follow_requests_sheet.dart';

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
              leading: const Icon(Icons.manage_accounts),
              title: const Text('アカウント設定'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/account-settings');
              },
            ),
            ListTile(
              leading: Consumer(
                builder: (ctx, ref, _) {
                  final accountId = ref.watch(activeAccountProvider)?.id ?? '';
                  final cnt = ref.watch(followRequestsBadgeProvider(accountId));
                  return cnt > 0
                      ? Badge(
                          label: Text('$cnt'),
                          child: const Icon(Icons.person_add),
                        )
                      : const Icon(Icons.person_add);
                },
              ),
              title: const Text('フォローリクエスト'),
              onTap: () {
                Navigator.of(context).pop();
                if (activeAccount == null) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) =>
                      FollowRequestsSheet(profileOwnerId: activeAccount.userId),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('検索'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/search');
              },
            ),
            ListTile(
              leading: Consumer(
                builder: (ctx, ref, _) {
                  final accountId = ref.watch(activeAccountProvider)?.id ?? '';
                  final ann = ref.watch(announcementsBadgeProvider(accountId));
                  return ann > 0
                      ? Badge(
                          label: Text('$ann'),
                          child: const Icon(Icons.campaign_outlined),
                        )
                      : const Icon(Icons.campaign_outlined);
                },
              ),
              title: const Text('お知らせ'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/announcements');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('ドライブ'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/drive');
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
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: const Text('ミュート・ブロック'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/mute-block');
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
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('アプリ情報'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/app-info');
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
              IconButton(
                icon: const Icon(Icons.manage_accounts),
                tooltip: 'アカウント管理',
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
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
                        backgroundImage: CachedNetworkImageProvider(
                          a.avatarUrl!,
                        ),
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
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('アカウントを追加'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                context.push('/login?addAccount=true');
              },
            ),
          ],
        ),
      ),
    );
  }
}
