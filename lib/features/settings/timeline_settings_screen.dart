import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/settings_provider.dart';

class TimelineSettingsScreen extends ConsumerWidget {
  const TimelineSettingsScreen({super.key});

  static const _tzOptions = [
    (label: 'デバイスの設定に従う', offset: null),
    (label: 'UTC-12 (IDLW)', offset: -12),
    (label: 'UTC-11 (SST)', offset: -11),
    (label: 'UTC-10 (HST)', offset: -10),
    (label: 'UTC-9 (AKST)', offset: -9),
    (label: 'UTC-8 (PST)', offset: -8),
    (label: 'UTC-7 (MST)', offset: -7),
    (label: 'UTC-6 (CST)', offset: -6),
    (label: 'UTC-5 (EST)', offset: -5),
    (label: 'UTC-4 (AST)', offset: -4),
    (label: 'UTC-3 (BRT)', offset: -3),
    (label: 'UTC-2', offset: -2),
    (label: 'UTC-1 (AZOT)', offset: -1),
    (label: 'UTC+0 (GMT)', offset: 0),
    (label: 'UTC+1 (CET)', offset: 1),
    (label: 'UTC+2 (EET)', offset: 2),
    (label: 'UTC+3 (MSK)', offset: 3),
    (label: 'UTC+4 (GST)', offset: 4),
    (label: 'UTC+5 (PKT)', offset: 5),
    (label: 'UTC+5:30 (IST)', offset: 6),
    (label: 'UTC+7 (WIB)', offset: 7),
    (label: 'UTC+8 (CST/HKT)', offset: 8),
    (label: 'UTC+9 (JST/KST)', offset: 9),
    (label: 'UTC+10 (AEST)', offset: 10),
    (label: 'UTC+11 (AEDT)', offset: 11),
    (label: 'UTC+12 (NZST)', offset: 12),
  ];

  static String _timezoneLabel(int? offset) {
    if (offset == null) return 'デバイスの設定に従う';
    final match = _tzOptions.where((o) => o.offset == offset).firstOrNull;
    if (match != null) return match.label;
    return offset >= 0 ? 'UTC+$offset' : 'UTC$offset';
  }

  Future<void> _pickTimezone(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final selected = await showDialog<({String label, int? offset})>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('タイムゾーンを選択'),
        children: _tzOptions.map((opt) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, opt),
            child: Text(
              opt.label,
              style: TextStyle(
                fontWeight: opt.offset == current
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      ref
          .read(settingsProvider.notifier)
          .setTimezoneOffsetHours(selected.offset);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('タイムライン表示')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('リアルタイム更新'),
            subtitle: const Text('WebSocketでタイムラインを自動更新する'),
            value: settings.realtimeUpdate,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setRealtimeUpdate(v),
          ),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.access_time_outlined),
            title: const Text('投稿日時を相対表示'),
            subtitle: Text(
              settings.dateTimeRelative ? '例: 3分前、2時間前' : '例: 2026/03/30 12:34',
            ),
            value: settings.dateTimeRelative,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setDateTimeRelative(v),
          ),
          if (!settings.dateTimeRelative)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('絶対時刻のタイムゾーン'),
              subtitle: Text(_timezoneLabel(settings.timezoneOffsetHours)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _pickTimezone(context, ref, settings.timezoneOffsetHours),
            ),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.animation_outlined),
            title: const Text('MFMアニメーション'),
            subtitle: const Text('スピン・レインボーなどのアニメーション効果を有効にする'),
            value: settings.mfmAnimation,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setMfmAnimation(v),
          ),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.unfold_less_outlined),
            title: const Text('長い投稿を省略表示'),
            subtitle: const Text('一定の高さを超えた投稿を折りたたみ「続きを読む」ボタンを表示する'),
            value: settings.collapseNote,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCollapseNote(v),
          ),
        ],
      ),
    );
  }
}
