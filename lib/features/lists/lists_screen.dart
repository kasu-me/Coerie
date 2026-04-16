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

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ListEditSheet(onSaved: _load),
    );
  }

  void _showEditSheet(Map<String, dynamic> list) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ListEditSheet(list: list, onSaved: _load),
    );
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
        onPressed: _showCreateSheet,
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
                if (value == 'edit') _showEditSheet(item);
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

// ---- リスト作成/編集ボトムシート ----

class _ListEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? list;
  final VoidCallback onSaved;

  const _ListEditSheet({this.list, required this.onSaved});

  @override
  ConsumerState<_ListEditSheet> createState() => _ListEditSheetState();
}

class _ListEditSheetState extends ConsumerState<_ListEditSheet> {
  final _nameController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.list;
    if (l != null) {
      _nameController.text = l['name'] as String? ?? '';
      _isPublic = l['isPublic'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('リスト名を入力してください')));
      return;
    }

    setState(() => _isSaving = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      if (widget.list == null) {
        final created = await api.createList(name: name);
        // isPublic は create では設定できないため、trueの場合は update で設定する
        if (_isPublic) {
          final listId = created['id'] as String?;
          if (listId != null) {
            await api.updateList(listId: listId, isPublic: true);
          }
        }
      } else {
        await api.updateList(
          listId: widget.list!['id'] as String,
          name: name,
          isPublic: _isPublic,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.list != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'リストを編集' : '新しいリストを作成',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: _save,
                    child: Text(isEditing ? '保存' : '作成'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'リスト名',
                    hintText: 'リストの名前を入力',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                  title: const Text('公開する'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
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
