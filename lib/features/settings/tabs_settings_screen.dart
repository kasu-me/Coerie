import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
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
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    // List.unmodifiableで保存されているため、必ず可変リストにコピーする
    _tabs = List<TabConfigModel>.from(ref.read(accountTabsProvider(accountId)));
  }

  Future<void> _save() async {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    // setTabs に渡す際も新しいコピーを渡して同一参照を避ける
    await ref
        .read(accountTabsProvider(accountId).notifier)
        .setTabs(List<TabConfigModel>.from(_tabs));
  }

  void _addTab() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
                        loader: () =>
                            ref.read(misskeyApiProvider)!.getAntennas(),
                        icon: Icons.settings_input_antenna,
                      );
                    } else if (e.key == AppConstants.tabTypeChannel) {
                      _pickAndAddSourceTab(
                        type: AppConstants.tabTypeChannel,
                        title: 'チャンネルを選択',
                        loader: () =>
                            ref.read(misskeyApiProvider)!.getChannelsFollowed(),
                        icon: Icons.tv,
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
      useSafeArea: true,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TabEditSheet(
        tab: tab,
        onSaved: (updated) {
          setState(() => _tabs[index] = updated);
          _save();
        },
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
    AppConstants.tabTypeChannel => Icons.tv,
    _ => Icons.tab,
  };
}

/// タブ編集BottomSheet
class _TabEditSheet extends StatefulWidget {
  final TabConfigModel tab;
  final void Function(TabConfigModel) onSaved;

  const _TabEditSheet({required this.tab, required this.onSaved});

  @override
  State<_TabEditSheet> createState() => _TabEditSheetState();
}

class _TabEditSheetState extends State<_TabEditSheet> {
  late TextEditingController _labelController;
  late bool? _withReplies;
  late bool? _withRenotes;
  late bool? _withFiles;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.tab.label);
    _withReplies = widget.tab.withReplies;
    _withRenotes = widget.tab.withRenotes;
    _withFiles = widget.tab.withFiles;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  bool get _supportsWithReplies =>
      widget.tab.type == AppConstants.tabTypeLocal ||
      widget.tab.type == AppConstants.tabTypeSocial;

  bool get _supportsWithRenotes =>
      widget.tab.type == AppConstants.tabTypeHome ||
      widget.tab.type == AppConstants.tabTypeLocal ||
      widget.tab.type == AppConstants.tabTypeSocial ||
      widget.tab.type == AppConstants.tabTypeGlobal ||
      widget.tab.type == AppConstants.tabTypeList;

  bool get _supportsWithFiles =>
      widget.tab.type == AppConstants.tabTypeHome ||
      widget.tab.type == AppConstants.tabTypeLocal ||
      widget.tab.type == AppConstants.tabTypeSocial ||
      widget.tab.type == AppConstants.tabTypeGlobal ||
      widget.tab.type == AppConstants.tabTypeList;

  bool get _hasOptions =>
      _supportsWithReplies || _supportsWithRenotes || _supportsWithFiles;

  void _save() {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;
    widget.onSaved(
      widget.tab.copyWith(
        label: label,
        withReplies: _withReplies,
        withRenotes: _withRenotes,
        withFiles: _withFiles,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'タブを編集',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _labelController,
                autofocus: !_hasOptions,
                decoration: const InputDecoration(
                  labelText: 'タブ名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
            ),
            if (_hasOptions) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '表示オプション',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (_supportsWithReplies)
                SwitchListTile(
                  secondary: const Icon(Icons.reply_outlined),
                  title: const Text('他の人へのリプライを表示'),
                  subtitle: const Text('フォロー外のユーザーへのリプライを含める'),
                  value: _withReplies ?? false,
                  onChanged: (v) => setState(() => _withReplies = v),
                ),
              if (_supportsWithRenotes)
                SwitchListTile(
                  secondary: const Icon(Icons.repeat_outlined),
                  title: const Text('リノートを表示'),
                  subtitle: const Text('OFFにするとリノートを除外する'),
                  value: _withRenotes ?? true,
                  onChanged: (v) => setState(() => _withRenotes = v),
                ),
              if (_supportsWithFiles)
                SwitchListTile(
                  secondary: const Icon(Icons.attach_file_outlined),
                  title: const Text('ファイル付きのみ'),
                  subtitle: const Text('添付ファイルがある投稿だけを表示する'),
                  value: _withFiles ?? false,
                  onChanged: (v) => setState(() => _withFiles = v),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
