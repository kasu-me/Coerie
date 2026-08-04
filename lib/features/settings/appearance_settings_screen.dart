import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/widgets/section_header.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('外観')),
      body: ListView(
        children: [
          // --- テーマ ---
          SectionHeader('テーマ'),
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
          SectionHeader('フォントサイズ'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
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

          // --- アイコンサイズ ---
          SectionHeader('アイコンサイズ'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${(settings.avatarRadius * 2).toStringAsFixed(0)}px'),
                Slider(
                  min: 12,
                  max: 40,
                  divisions: 28,
                  value: settings.avatarRadius,
                  label: '${(settings.avatarRadius * 2).toStringAsFixed(0)}px',
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setAvatarRadius(v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [Text('小'), Text('大')],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

