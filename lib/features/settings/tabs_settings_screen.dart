import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../data/models/app_settings_model.dart';
import '../../core/constants/app_constants.dart';

class TabsSettingsScreen extends ConsumerStatefulWidget {
  const TabsSettingsScreen({super.key});

  @override
  ConsumerState<TabsSettingsScreen> createState() => _TabsSettingsScreenState();
}

class _TabsSettingsScreenState extends ConsumerState<TabsSettingsScreen> {
  late List<TabConfigModel> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = List.from(ref.read(settingsProvider).tabs);
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setTabs(_tabs);
  }

  void _addTab() {
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
                'タブの種類を選択',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...AppConstants.tabTypeLabels.entries.map(
              (e) => ListTile(
                leading: Icon(_tabIcon(e.key)),
                title: Text(e.value),
                onTap: () {
                  Navigator.pop(context);
                  if (e.key == AppConstants.tabTypeList) {
                    _pickAndAddSourceTab(
                      type: AppConstants.tabTypeList,
                      title: 'リストを選択',
                      loader: () => ref.read(misskeyApiProvider)!.getLists(),
                      icon: Icons.list,
                    );
                  } else if (e.key == AppConstants.tabTypeAntenna) {
                    _pickAndAddSourceTab(
                      type: AppConstants.tabTypeAntenna,
                      title: 'アンテナを選択',
                      loader: () => ref.read(misskeyApiProvider)!.getAntennas(),
                      icon: Icons.settings_input_antenna,
                    );
                  } else {
                    _showLabelInput(e.key, e.value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLabelInput(String type, String defaultLabel, {String? sourceId}) {
    final controller = TextEditingController(text: defaultLabel);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('タブ名を入力'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final label = controller.text.trim().isEmpty
                  ? defaultLabel
                  : controller.text.trim();
              setState(() {
                _tabs.add(
                  TabConfigModel(
                    id: const Uuid().v4(),
                    label: label,
                    type: type,
                    sourceId: sourceId,
                  ),
                );
              });
              _save();
              Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndAddSourceTab({
    required String type,
    required String title,
    required Future<List<Map<String, dynamic>>> Function() loader,
    required IconData icon,
  }) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    // ignore: use_build_context_synchronously
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: loader(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 200,
                child: Center(child: Text('読み込みエラー: ${snapshot.error}')),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(child: Text('$titleがありません')),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                ...items.map(
                  (item) => ListTile(
                    leading: Icon(icon),
                    title: Text(item['name'] as String? ?? ''),
                    onTap: () => Navigator.pop(ctx, item),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (selected == null || !mounted) return;
    _showLabelInput(
      type,
      selected['name'] as String? ?? AppConstants.tabTypeLabels[type]!,
      sourceId: selected['id'] as String,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('タブの管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'タブを追加',
            onPressed: _addTab,
          ),
        ],
      ),
      body: _tabs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.tab_unselected,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  const Text('タブがありません'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _addTab,
                    icon: const Icon(Icons.add),
                    label: const Text('タブを追加'),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              itemCount: _tabs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final tab = _tabs.removeAt(oldIndex);
                  _tabs.insert(newIndex, tab);
                });
                _save();
              },
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                return ListTile(
                  key: Key(tab.id),
                  leading: Icon(_tabIcon(tab.type)),
                  title: Text(tab.label),
                  subtitle: Text(
                    AppConstants.tabTypeLabels[tab.type] ?? tab.type,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editTab(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _tabs.removeAt(index));
                          _save();
                        },
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _editTab(int index) {
    final tab = _tabs[index];
    final controller = TextEditingController(text: tab.label);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('タブ名を編集'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _tabs[index] = tab.copyWith(label: controller.text.trim());
                });
                _save();
              }
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  IconData _tabIcon(String type) => switch (type) {
    AppConstants.tabTypeHome => Icons.home_outlined,
    AppConstants.tabTypeLocal => Icons.people_outline,
    AppConstants.tabTypeSocial => Icons.group_outlined,
    AppConstants.tabTypeGlobal => Icons.public,
    AppConstants.tabTypeNotifications => Icons.notifications_outlined,
    AppConstants.tabTypeList => Icons.list,
    AppConstants.tabTypeAntenna => Icons.settings_input_antenna,
    _ => Icons.tab,
  };
}
