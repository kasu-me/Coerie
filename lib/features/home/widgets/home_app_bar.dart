import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../shared/providers/notifications_badge_provider.dart';
import '../../../shared/providers/announcements_badge_provider.dart';
import '../../../shared/providers/dm_badge_provider.dart';
import '../../../shared/widgets/user_avatar.dart';

class HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;

  const HomeAppBar({super.key, required this.scaffoldKey});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    final accountId = account?.id ?? '';
    final unread = ref.watch(notificationsBadgeProvider(accountId));
    final annUnread = ref.watch(announcementsBadgeProvider(accountId));
    final dmUnread = ref.watch(dmBadgeProvider(accountId));

    final avatar = UserAvatar(avatarUrl: account?.avatarUrl, iconSize: 20);

    return AppBar(
      automaticallyImplyLeading: false,
      // タイムラインは TabBarView 内にあり depth>0 のため元々 scrolledUnder は
      // 効いていない。誤検知でヘッダに色が付くのを防ぐため常に無効化する。
      notificationPredicate: (_) => false,
      leading: GestureDetector(
        onTap: () => scaffoldKey.currentState?.openDrawer(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: dmUnread > 0
              ? Badge(label: Text('$dmUnread'), child: avatar)
              : avatar,
        ),
      ),
      title: const Text(
        'Coerie',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
      actions: [
        IconButton(
          icon: annUnread > 0
              ? Badge(
                  label: Text('$annUnread'),
                  child: const Icon(Icons.campaign_outlined),
                )
              : const Icon(Icons.campaign_outlined),
          tooltip: 'お知らせ',
          onPressed: () {
            // Just open announcements; do not auto-mark as read.
            context.push('/announcements');
          },
        ),
        IconButton(
          icon: unread > 0
              ? Badge(
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                )
              : const Icon(Icons.notifications_outlined),
          tooltip: '通知',
          onPressed: () {
            ref.read(notificationsBadgeProvider(accountId).notifier).clear();
            context.push('/notifications');
          },
        ),
      ],
    );
  }
}
