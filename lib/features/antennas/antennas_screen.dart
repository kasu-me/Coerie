import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';

class AntennasScreen extends ConsumerStatefulWidget {
  const AntennasScreen({super.key});

  @override
  ConsumerState<AntennasScreen> createState() => _AntennasScreenState();
}

class _AntennasScreenState extends ConsumerState<AntennasScreen> {
  List<Map<String, dynamic>> _items = [];
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
      final items = await api.getAntennas();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditSheet({Map<String, dynamic>? antenna}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _AntennaEditSheet(antenna: antenna, onSaved: _load),
    );
  }

  Future<void> _deleteAntenna(Map<String, dynamic> antenna) async {
    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('アンテナを削除'),
          content: Text('「${antenna['name']}」を削除しますか？この操作は取り消せません。'),
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
      await api.deleteAntenna(antennaId: antenna['id'] as String);
      await _load();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('アンテナ'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditSheet(),
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

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.settings_input_antenna,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text('アンテナがありません'),
            const SizedBox(height: 8),
            const Text(
              '右下の + ボタンでアンテナを作成できます',
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
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = _items[i];
          final id = item['id'] as String? ?? '';
          final name = item['name'] as String? ?? '';
          return ListTile(
            leading: const Icon(Icons.settings_input_antenna),
            title: Text(name),
            subtitle: Text(
              _srcLabel(item['src'] as String? ?? 'all'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _showEditSheet(antenna: item);
                if (value == 'delete') _deleteAntenna(item);
              },
              itemBuilder: (_) => [
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
            onTap: () => context.push('/antenna/$id', extra: item),
          );
        },
      ),
    );
  }

  String _srcLabel(String src) {
    switch (src) {
      case 'all':
        return '全てのノート';
      case 'users':
        return '指定ユーザーのノート';
      case 'users_blacklist':
        return '指定ユーザーを除いた全てのノート';
      case 'home':
        return 'ホームタイムライン';
      case 'list':
        return 'リストのノート';
      default:
        return src;
    }
  }
}

// ---- アンテナ作成/編集ボトムシート ----

class _AntennaEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? antenna;
  final VoidCallback onSaved;

  const _AntennaEditSheet({this.antenna, required this.onSaved});

  @override
  ConsumerState<_AntennaEditSheet> createState() => _AntennaEditSheetState();
}

class _AntennaEditSheetState extends ConsumerState<_AntennaEditSheet> {
  final _nameController = TextEditingController();
  final _keywordsController = TextEditingController();
  final _excludeKeywordsController = TextEditingController();

  String _src = 'all';
  bool _excludeBots = false;
  bool _withReplies = false;
  bool _withFile = false;
  bool _localOnly = false;
  bool _caseSensitive = false;
  bool _excludeNotesInSensitiveChannel = false;

  // ユーザー一覧（users / users_blacklist のとき使う）
  // 各要素は {id, username, host, name, avatarUrl} の Map
  List<Map<String, dynamic>> _selectedUsers = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.antenna;
    if (a != null) {
      _nameController.text = a['name'] as String? ?? '';
      _src = a['src'] as String? ?? 'all';
      _excludeBots = a['excludeBots'] as bool? ?? false;
      _withReplies = a['withReplies'] as bool? ?? false;
      _withFile = a['withFile'] as bool? ?? false;
      _localOnly = a['localOnly'] as bool? ?? false;
      _caseSensitive = a['caseSensitive'] as bool? ?? false;
      _excludeNotesInSensitiveChannel =
          a['excludeNotesInSensitiveChannel'] as bool? ?? false;

      // keywords: [[w1, w2], [w3]] → "w1 w2\nw3"
      final kw = a['keywords'] as List<dynamic>?;
      if (kw != null) {
        _keywordsController.text = kw
            .map(
              (row) =>
                  (row as List<dynamic>).map((w) => w.toString()).join(' '),
            )
            .where((s) => s.isNotEmpty)
            .join('\n');
      }
      final ekw = a['excludeKeywords'] as List<dynamic>?;
      if (ekw != null) {
        _excludeKeywordsController.text = ekw
            .map(
              (row) =>
                  (row as List<dynamic>).map((w) => w.toString()).join(' '),
            )
            .where((s) => s.isNotEmpty)
            .join('\n');
      }

      // users: ["@username@host", ...] → user map list
      final users = a['users'] as List<dynamic>?;
      if (users != null) {
        _selectedUsers = users.map((u) {
          final acct = u.toString();
          final parts = acct.replaceFirst('@', '').split('@');
          return {
            'acct': acct,
            'username': parts.isNotEmpty ? parts[0] : acct,
            'host': parts.length > 1 ? parts[1] : null,
          };
        }).toList();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keywordsController.dispose();
    _excludeKeywordsController.dispose();
    super.dispose();
  }

  bool get _needsUsers => _src == 'users' || _src == 'users_blacklist';

  List<List<String>> _parseKeywords(String text) {
    if (text.trim().isEmpty) return [[]];
    return text
        .split('\n')
        .map(
          (line) => line.trim().split(' ').where((w) => w.isNotEmpty).toList(),
        )
        .where((row) => row.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('アンテナ名を入力してください')));
      return;
    }

    final keywords = _parseKeywords(_keywordsController.text);
    final excludeKeywords = _parseKeywords(_excludeKeywordsController.text);

    // キーワードが全て空の場合はエラー
    if (keywords.every((row) => row.isEmpty) &&
        excludeKeywords.every((row) => row.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('受信キーワードまたは除外キーワードを入力してください')),
      );
      return;
    }

    final users = _selectedUsers.map((u) {
      final acct = u['acct'] as String?;
      if (acct != null) return acct;
      final username = u['username'] as String? ?? '';
      final host = u['host'] as String?;
      return host != null ? '@$username@$host' : '@$username';
    }).toList();

    setState(() => _isSaving = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      if (widget.antenna == null) {
        await api.createAntenna(
          name: name,
          src: _src,
          keywords: keywords,
          excludeKeywords: excludeKeywords,
          users: users,
          caseSensitive: _caseSensitive,
          withReplies: _withReplies,
          withFile: _withFile,
          localOnly: _localOnly,
          excludeBots: _excludeBots,
          excludeNotesInSensitiveChannel: _excludeNotesInSensitiveChannel,
        );
      } else {
        await api.updateAntenna(
          antennaId: widget.antenna!['id'] as String,
          name: name,
          src: _src,
          keywords: keywords,
          excludeKeywords: excludeKeywords,
          users: users,
          caseSensitive: _caseSensitive,
          withReplies: _withReplies,
          withFile: _withFile,
          localOnly: _localOnly,
          excludeBots: _excludeBots,
          excludeNotesInSensitiveChannel: _excludeNotesInSensitiveChannel,
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
    final acct = selectedUser.acct;
    // 重複チェック
    final alreadyAdded = _selectedUsers.any((u) {
      final existing =
          u['acct'] as String? ??
          (u['host'] != null
              ? '@${u['username']}@${u['host']}'
              : '@${u['username']}');
      return existing == acct;
    });
    if (!alreadyAdded) {
      setState(() {
        _selectedUsers.add({
          'acct': acct,
          'username': selectedUser.username,
          'host': selectedUser.host.isEmpty ? null : selectedUser.host,
          'name': selectedUser.name,
          'avatarUrl': selectedUser.avatarUrl,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.antenna != null;
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
                    isEditing ? 'アンテナを編集' : '新しいアンテナを作成',
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
                // アンテナ名
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'アンテナ名',
                    hintText: 'アンテナの名前を入力',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // 受信ソース
                Text('受信ソース', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _SrcSelector(
                  value: _src,
                  onChanged: (v) => setState(() => _src = v),
                ),
                const SizedBox(height: 16),

                // ユーザー選択
                if (_needsUsers) ...[
                  Row(
                    children: [
                      Text(
                        _src == 'users' ? '対象ユーザー' : 'ブラックリストユーザー',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('追加'),
                        onPressed: _showAddUserDialog,
                      ),
                    ],
                  ),
                  if (_selectedUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'ユーザーが選択されていません',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...List.generate(_selectedUsers.length, (i) {
                      final user = _selectedUsers[i];
                      final name =
                          user['name'] as String? ??
                          user['username'] as String? ??
                          '';
                      final acct =
                          user['acct'] as String? ??
                          (user['host'] != null
                              ? '@${user['username']}@${user['host']}'
                              : '@${user['username']}');
                      final avatarUrl = user['avatarUrl'] as String?;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: avatarUrl != null
                            ? CircleAvatar(
                                backgroundImage: NetworkImage(avatarUrl),
                                radius: 16,
                              )
                            : const CircleAvatar(
                                radius: 16,
                                child: Icon(Icons.person, size: 16),
                              ),
                        title: Text(name),
                        subtitle: Text(
                          acct,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () =>
                              setState(() => _selectedUsers.removeAt(i)),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                ],

                // 受信キーワード
                Text('受信キーワード', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'スペース区切りでAND指定、改行区切りでOR指定',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keywordsController,
                  decoration: const InputDecoration(
                    hintText: 'キーワード1 キーワード2\nキーワード3',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                  minLines: 3,
                ),
                const SizedBox(height: 20),

                // 除外キーワード
                Text('除外キーワード', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'スペース区切りでAND指定、改行区切りでOR指定',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _excludeKeywordsController,
                  decoration: const InputDecoration(
                    hintText: '除外したいキーワード',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                  minLines: 3,
                ),
                const SizedBox(height: 20),

                // トグル設定
                Text('フィルター設定', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _ToggleTile(
                  title: 'Botアカウントを除外',
                  value: _excludeBots,
                  onChanged: (v) => setState(() => _excludeBots = v),
                ),
                _ToggleTile(
                  title: '返信を含む',
                  value: _withReplies,
                  onChanged: (v) => setState(() => _withReplies = v),
                ),
                _ToggleTile(
                  title: 'ローカルのみ',
                  value: _localOnly,
                  onChanged: (v) => setState(() => _localOnly = v),
                ),
                _ToggleTile(
                  title: '大文字小文字を区別する',
                  value: _caseSensitive,
                  onChanged: (v) => setState(() => _caseSensitive = v),
                ),
                _ToggleTile(
                  title: 'ファイル添付ノートのみ',
                  value: _withFile,
                  onChanged: (v) => setState(() => _withFile = v),
                ),
                _ToggleTile(
                  title: 'センシティブなノートを含む',
                  subtitle: 'センシティブなチャンネルのノートを受信します',
                  value: !_excludeNotesInSensitiveChannel,
                  onChanged: (v) =>
                      setState(() => _excludeNotesInSensitiveChannel = !v),
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

class _SrcSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SrcSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', '全てのノート'),
      ('users', '指定ユーザーのノート'),
      ('users_blacklist', '指定ユーザーを除いた全てのノート'),
    ];
    return Column(
      children: options.map((opt) {
        final (src, label) = opt;
        return RadioListTile<String>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: src,
          groupValue: value,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      }).toList(),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}
