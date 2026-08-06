import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/drawer_button_type.dart';
import '../../shared/providers/settings_provider.dart';

class DrawerButtonSettingsScreen extends ConsumerWidget {
  const DrawerButtonSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hiddenButtons = ref
        .watch(settingsProvider)
        .hiddenDrawerButtons
        .toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('ドロワーボタン')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'ホーム画面のドロワーに表示するボタンを選択できます。\n'
              'アカウント関連の項目、アプリ設定、アプリ情報は常に表示されます。',
            ),
          ),
          const Divider(height: 1),
          for (final info in kCustomizableDrawerButtons)
            SwitchListTile(
              secondary: Icon(info.icon),
              title: Text(info.label),
              value: !hiddenButtons.contains(info.key.name),
              onChanged: (visible) => ref
                  .read(settingsProvider.notifier)
                  .setDrawerButtonHidden(info.key, !visible),
            ),
        ],
      ),
    );
  }
}
