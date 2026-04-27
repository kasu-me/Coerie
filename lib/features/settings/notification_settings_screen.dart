import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/settings_provider.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('プッシュ通知'),
            subtitle: const Text('アプリへのプッシュ通知を受け取る'),
            value: settings.notificationsEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setNotificationsEnabled(v),
          ),
          if (settings.notificationsEnabled) ...[
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '通知の種類',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.reply_outlined),
              title: const Text('返信'),
              value: settings.notifyReply,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyReply(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.person_add_outlined),
              title: const Text('フォロー'),
              value: settings.notifyFollow,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyFollow(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.add_reaction_outlined),
              title: const Text('リアクション'),
              value: settings.notifyReaction,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNotifyReaction(v),
            ),
          ],
        ],
      ),
    );
  }
}
