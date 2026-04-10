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
    if (api == null) return;
    try {
      final clips = await api.getClips(userId: widget.ownerUserId);
      if (mounted) setState(() => _clips = clips);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新しいクリップを作成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'タイトル',
                  hintText: 'クリップのタイトルを入力',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '説明（任意）',
                  hintText: '説明を入力',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: isPublic,
                    onChanged: (v) =>
                        setDialogState(() => isPublic = v ?? false),
                  ),
                  const Text('公開する'),
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
      await api.createClip(
        name: name,
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
        isPublic: isPublic,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('作成に失敗しました: $e')));
      }
    }
  }

  Future<void> _showEditDialog(ClipModel clip) async {
    final nameController = TextEditingController(text: clip.name);
    final descController = TextEditingController(text: clip.description ?? '');
    bool isPublic = clip.isPublic;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('クリップを編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'タイトル'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '説明（任意）'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: isPublic,
                    onChanged: (v) =>
                        setDialogState(() => isPublic = v ?? false),
                  ),
                  const Text('公開する'),
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
      await api.updateClip(
        clipId: clip.id,
        name: name,
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: isOwn
          ? FloatingActionButton(
              onPressed: _showCreateDialog,
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
                    if (value == 'edit') _showEditDialog(clip);
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
