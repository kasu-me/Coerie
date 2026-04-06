import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_provider.dart';
import '../../../shared/providers/notifications_badge_provider.dart';
import '../../../shared/providers/announcements_badge_provider.dart';

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

    return AppBar(
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: () => scaffoldKey.currentState?.openDrawer(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: account?.avatarUrl != null
              ? CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(
                    account!.avatarUrl!,
                  ),
                )
              : const CircleAvatar(child: Icon(Icons.person, size: 20)),
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
