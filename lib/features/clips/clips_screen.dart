import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../data/models/clip_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';

class ClipsScreen extends ConsumerStatefulWidget {
  final String? ownerUserId;
  final String? ownerUserName;

  const ClipsScreen({super.key, this.ownerUserId, this.ownerUserName});

  @override
  ConsumerState<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends ConsumerState<ClipsScreen> {
  List<ClipModel> _clips = [];
  bool _isLoading = false;
  String? _error;
  // false: newest first (降順), true: oldest first (昇順)
  bool _ascending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _sortClips() {
    _clips.sort((a, b) {
      return _ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final clips = await api.getClips(userId: widget.ownerUserId);
      if (mounted)
        setState(() {
          _clips = clips;
          _sortClips();
        });
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
      builder: (ctx) => _ClipEditSheet(onSaved: _load),
    );
  }

  void _showEditSheet(ClipModel clip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ClipEditSheet(clip: clip, onSaved: _load),
    );
  }

  Future<void> _deleteClip(ClipModel clip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('クリップを削除'),
        content: Text('「${clip.name}」を削除しますか？この操作は取り消せません。'),
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

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteClip(clip.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _copyClipUrl(ClipModel clip) async {
    final active = ref.read(activeAccountProvider);
    final host = active?.host ?? '';
    if (host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URLをコピーできませんでした')));
      }
      return;
    }
    final url = 'https://$host/clips/${clip.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URLをコピーしました'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.read(activeAccountProvider);
    final isOwn =
        widget.ownerUserId == null || widget.ownerUserId == active?.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ownerUserName != null
              ? '${widget.ownerUserName} のクリップ'
              : 'クリップ',
        ),
        actions: [
          IconButton(
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _ascending ? '古い順（昇順）' : '新しい順（降順）',
            onPressed: () {
              setState(() {
                _ascending = !_ascending;
                _sortClips();
              });
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: isOwn
          ? FloatingActionButton(
              onPressed: _showCreateSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(bottom: true, child: _buildBody(isOwn)),
    );
  }

  Widget _buildBody(bool isOwn) {
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
            FilledButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_clips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(widget.ownerUserId == null ? 'クリップがありません' : '公開クリップがありません'),
            const SizedBox(height: 8),
            Text(
              widget.ownerUserId == null
                  ? '右下の + ボタンでクリップを作成できます'
                  : 'このユーザーは公開クリップを持っていないか、\nサーバーがこの機能に対応していません',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _clips.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final clip = _clips[i];
          return ListTile(
            leading: Icon(
              clip.isPublic ? Icons.bookmark : Icons.bookmark_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(clip.name),
            subtitle: clip.description != null
                ? Text(
                    clip.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (clip.notesCount != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${clip.notesCount}件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'copy') _copyClipUrl(clip);
                    if (value == 'edit') _showEditSheet(clip);
                    if (value == 'delete') _deleteClip(clip);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: const [
                          Icon(Icons.copy),
                          SizedBox(width: 8),
                          Text('URLをコピー'),
                        ],
                      ),
                    ),
                    if (isOwn) ...[
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
                  ],
                ),
              ],
            ),
            onTap: () => context.push('/clips/${clip.id}', extra: clip),
          );
        },
      ),
    );
  }
}

// ---- クリップ作成/編集ボトムシート ----

class _ClipEditSheet extends ConsumerStatefulWidget {
  final ClipModel? clip;
  final VoidCallback onSaved;

  const _ClipEditSheet({this.clip, required this.onSaved});

  @override
  ConsumerState<_ClipEditSheet> createState() => _ClipEditSheetState();
}

class _ClipEditSheetState extends ConsumerState<_ClipEditSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.clip;
    if (c != null) {
      _nameController.text = c.name;
      _descController.text = c.description ?? '';
      _isPublic = c.isPublic;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
      return;
    }

    setState(() => _isSaving = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      if (widget.clip == null) {
        await api.createClip(
          name: name,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          isPublic: _isPublic,
        );
      } else {
        await api.updateClip(
          clipId: widget.clip!.id,
          name: name,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
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
    final isEditing = widget.clip != null;
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
                    isEditing ? 'クリップを編集' : '新しいクリップを作成',
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
                    labelText: 'タイトル',
                    hintText: 'クリップのタイトルを入力',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: '説明（任意）',
                    hintText: '説明を入力',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
