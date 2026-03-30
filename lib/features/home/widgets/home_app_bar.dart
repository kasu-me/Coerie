import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_provider.dart';

class HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;

  const HomeAppBar({super.key, required this.scaffoldKey});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);

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
          icon: const Icon(Icons.notifications_outlined),
          tooltip: '通知',
          onPressed: () => context.push('/notifications'),
        ),
      ],
    );
  }
}
