import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings_model.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';

class ListsScreen extends ConsumerStatefulWidget {
  const ListsScreen({super.key});

  @override
  ConsumerState<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends ConsumerState<ListsScreen> {
  List<Map<String, dynamic>> _lists = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _error = 'ログインが必要です';
        });
      return;
    }

    try {
      final items = await api.getLists();
      if (mounted) setState(() => _lists = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    bool isPublic = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新しいリストを作成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'リスト名',
                  hintText: 'リストの名前を入力',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: isPublic,
                    onChanged: (v) =>
                        setDialogState(() => isPublic = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  GestureDetector(
                    onTap: () => setDialogState(() => isPublic = !isPublic),
                    child: const Text('公開する'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('作成'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final created = await api.createList(name: name);
      // isPublic は create では設定できないため、trueの場合は update で設定する
      if (isPublic) {
        final listId = created['id'] as String?;
        if (listId != null) {
          await api.updateList(listId: listId, isPublic: true);
        }
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('作成に失敗しました: $e')));
      }
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> list) async {
    final nameController = TextEditingController(
      text: list['name'] as String? ?? '',
    );
    bool isPublic = list['isPublic'] as bool? ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('リストを編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'リスト名'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: isPublic,
                    onChanged: (v) =>
                        setDialogState(() => isPublic = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  GestureDetector(
                    onTap: () => setDialogState(() => isPublic = !isPublic),
                    child: const Text('公開する'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.updateList(
        listId: list['id'] as String,
        name: name,
        isPublic: isPublic,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
      }
    }
  }

  Future<void> _deleteList(Map<String, dynamic> list) async {
    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('リストを削除'),
          content: Text('「${list['name']}」を削除しますか？この操作は取り消せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteList(listId: list['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _addToHomeTab(Map<String, dynamic> list) async {
    final name = list['name'] as String? ?? 'リスト';
    final id = list['id'] as String? ?? '';
    final labelController = TextEditingController(text: name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ホームタブに追加'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: 'タブ名',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final label = labelController.text.trim().isEmpty
        ? name
        : labelController.text.trim();
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    final currentTabs = List<TabConfigModel>.from(
      ref.read(accountTabsProvider(accountId)),
    );
    currentTabs.add(
      TabConfigModel(
        id: const Uuid().v4(),
        label: label,
        type: AppConstants.tabTypeList,
        sourceId: id,
      ),
    );
    await ref
        .read(accountTabsProvider(accountId).notifier)
        .setTabs(currentTabs);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「$label」タブを追加しました')));
    }
  }

  void _showMembersSheet(Map<String, dynamic> list) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ListMembersSheet(list: list),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('リスト'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('エラーが発生しました', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }

    if (_lists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.list, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('リストがありません'),
            const SizedBox(height: 8),
            const Text(
              '右下の + ボタンでリストを作成できます',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _lists.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = _lists[i];
          final id = item['id'] as String? ?? '';
          final name = item['name'] as String? ?? '';
          final isPublic = item['isPublic'] as bool? ?? false;
          return ListTile(
            leading: Icon(
              isPublic ? Icons.list : Icons.lock_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(name),
            subtitle: isPublic ? const Text('公開') : null,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'add_tab') _addToHomeTab(item);
                if (value == 'edit') _showEditDialog(item);
                if (value == 'members') _showMembersSheet(item);
                if (value == 'delete') _deleteList(item);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'add_tab',
                  child: Row(
                    children: [
                      Icon(Icons.add_to_photos_outlined),
                      SizedBox(width: 8),
                      Text('ホームタブに追加'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 8),
                      Text('編集'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'members',
                  child: Row(
                    children: [
                      Icon(Icons.people_outline),
                      SizedBox(width: 8),
                      Text('メンバー管理'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 8),
                      Text('削除'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => context.push('/list/$id', extra: item),
          );
        },
      ),
    );
  }
}

// ---- メンバー管理ボトムシート ----

class _ListMembersSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> list;
  const _ListMembersSheet({required this.list});

  @override
  ConsumerState<_ListMembersSheet> createState() => _ListMembersSheetState();
}

class _ListMembersSheetState extends ConsumerState<_ListMembersSheet> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final listId = widget.list['id'] as String;
      final memberships = await api.getListMembers(listId: listId);
      if (mounted) setState(() => _members = memberships);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddUserDialog() async {
    final searchController = TextEditingController();
    List<UserModel> results = [];
    bool isSearching = false;

    final selectedUser = await showDialog<UserModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ユーザーを追加'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'ユーザー名で検索',
                    hintText: '@username',
                    suffixIcon: IconButton(
                      icon: isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      onPressed: () async {
                        final query = searchController.text.trim();
                        if (query.isEmpty) return;
                        setDialogState(() => isSearching = true);
                        try {
                          final api = ref.read(misskeyApiProvider);
                          if (api == null) return;
                          final res = await api.searchUsers(query: query);
                          setDialogState(() => results = res);
                        } catch (_) {
                        } finally {
                          setDialogState(() => isSearching = false);
                        }
                      },
                    ),
                  ),
                  onSubmitted: (query) async {
                    if (query.trim().isEmpty) return;
                    setDialogState(() => isSearching = true);
                    try {
                      final api = ref.read(misskeyApiProvider);
                      if (api == null) return;
                      final res = await api.searchUsers(query: query.trim());
                      setDialogState(() => results = res);
                    } catch (_) {
                    } finally {
                      setDialogState(() => isSearching = false);
                    }
                  },
                ),
                const SizedBox(height: 8),
                if (results.isEmpty && !isSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'ユーザー名を入力して検索してください',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final user = results[i];
                        return ListTile(
                          dense: true,
                          leading: user.avatarUrl != null
                              ? CircleAvatar(
                                  backgroundImage: NetworkImage(
                                    user.avatarUrl!,
                                  ),
                                  radius: 16,
                                )
                              : const CircleAvatar(
                                  radius: 16,
                                  child: Icon(Icons.person, size: 16),
                                ),
                          title: Text(user.name),
                          subtitle: Text(
                            user.acct,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                          onTap: () => Navigator.pop(ctx, user),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),
    );

    if (selectedUser == null || !mounted) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.addListMember(
        listId: widget.list['id'] as String,
        userId: selectedUser.id,
      );
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
      }
    }
  }

  Future<void> _removeMember(Map<String, dynamic> membership) async {
    final user = membership['user'] as Map<String, dynamic>?;
    if (user == null) return;
    final userId = user['id'] as String?;
    if (userId == null) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.removeListMember(
        listId: widget.list['id'] as String,
        userId: userId,
      );
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listName = widget.list['name'] as String? ?? 'リスト';
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$listName のメンバー',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadMembers,
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'ユーザーを追加',
                  onPressed: _showAddUserDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildMemberList(scrollController)),
        ],
      ),
    );
  }

  Widget _buildMemberList(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('エラーが発生しました', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadMembers, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('メンバーがいません'),
            const SizedBox(height: 8),
            const Text(
              '右上の + ボタンでユーザーを追加できます',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      itemCount: _members.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final membership = _members[i];
        final user = membership['user'] as Map<String, dynamic>? ?? {};
        final name =
            user['name'] as String? ?? user['username'] as String? ?? '';
        final username = user['username'] as String? ?? '';
        final userHost = user['host'] as String?;
        final acct = userHost != null ? '@$username@$userHost' : '@$username';
        final avatarUrl = user['avatarUrl'] as String?;
        return ListTile(
          leading: avatarUrl != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(avatarUrl),
                  radius: 20,
                )
              : const CircleAvatar(radius: 20, child: Icon(Icons.person)),
          title: Text(name),
          subtitle: Text(acct, style: Theme.of(ctx).textTheme.bodySmall),
          trailing: IconButton(
            icon: Icon(
              Icons.person_remove_outlined,
              color: Theme.of(ctx).colorScheme.error,
            ),
            tooltip: 'リストから削除',
            onPressed: () => _removeMember(membership),
          ),
        );
      },
    );
  }
}
