import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/media_player_screen.dart';

/// ドライブフォルダの簡易モデル
class _DriveFolder {
  final String id;
  final String name;
  const _DriveFolder({required this.id, required this.name});

  factory _DriveFolder.fromJson(Map<String, dynamic> json) =>
      _DriveFolder(id: json['id'] as String, name: json['name'] as String);
}

class DriveScreen extends ConsumerStatefulWidget {
  /// trueのとき選択モード（投稿画面からの呼び出し）
  final bool selectionMode;

  /// 選択モードのとき選択できる最大件数
  final int maxSelection;

  const DriveScreen({
    super.key,
    this.selectionMode = false,
    this.maxSelection = 4,
  });

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  // パンくずスタック（最初はルート）
  final List<({String? id, String name})> _breadcrumbs = [
    (id: null, name: 'ドライブ'),
  ];

  List<_DriveFolder> _folders = [];
  List<DriveFileModel> _files = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();
  final Set<String> _selectedIds = {};
  bool _managingMode = false;
  bool _isUploading = false;

  String? get _currentFolderId => _breadcrumbs.last.id;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoading &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadMoreFiles();
    }
  }

  /// 現在のフォルダの内容（フォルダ + ファイル）を最初から取得
  Future<void> _load() async {
    setState(() {
      _folders = [];
      _files = [];
      _hasMore = true;
      _error = null;
      _isLoading = true;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final folderMaps = await api.getDriveFolders(folderId: _currentFolderId);
      final files = await api.getDriveFiles(
        limit: 40,
        folderId: _currentFolderId,
      );
      setState(() {
        _folders = folderMaps.map(_DriveFolder.fromJson).toList();
        _files = files;
        _hasMore = files.length >= 40;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// ファイルの追加読み込み
  Future<void> _loadMoreFiles() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final api = ref.read(misskeyApiProvider);
      if (api == null) return;
      final more = await api.getDriveFiles(
        limit: 40,
        untilId: _files.isNotEmpty ? _files.last.id : null,
        folderId: _currentFolderId,
      );
      setState(() {
        _files.addAll(more);
        _hasMore = more.length >= 40;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _openFolder(_DriveFolder folder) {
    setState(() {
      _breadcrumbs.add((id: folder.id, name: folder.name));
      _selectedIds.clear();
      _managingMode = false;
    });
    _load();
  }

  void _navigateToBreadcrumb(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      _selectedIds.clear();
      _managingMode = false;
    });
    _load();
  }

  void _onFileTap(DriveFileModel file) {
    if (widget.selectionMode) {
      setState(() {
        if (_selectedIds.contains(file.id)) {
          _selectedIds.remove(file.id);
        } else {
          if (_selectedIds.length >= widget.maxSelection) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('最大${widget.maxSelection}件まで選択できます'),
                duration: const Duration(seconds: 1),
              ),
            );
            return;
          }
          _selectedIds.add(file.id);
        }
      });
    } else if (_managingMode) {
      setState(() {
        if (_selectedIds.contains(file.id)) {
          _selectedIds.remove(file.id);
          if (_selectedIds.isEmpty) _managingMode = false;
        } else {
          _selectedIds.add(file.id);
        }
      });
    } else {
      _previewFile(file);
    }
  }

  void _enterManagingMode(DriveFileModel file) {
    setState(() {
      _managingMode = true;
      _selectedIds.add(file.id);
    });
  }

  void _exitManagingMode() {
    setState(() {
      _managingMode = false;
      _selectedIds.clear();
    });
  }

  void _previewFile(DriveFileModel file) {
    if (file.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DriveImagePreviewScreen(file: file),
        ),
      );
    } else if (file.isVideo || file.isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MediaPlayerScreen(
            url: file.url,
            title: file.name,
            isAudio: file.isAudio,
          ),
        ),
      );
    } else {
      launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication);
    }
  }

  void _createNoteFromFile(DriveFileModel file) {
    context.push(
      '/compose',
      extra: {
        'initialFiles': [file],
      },
    );
  }

  void _showFileMenu(DriveFileModel file) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('プレビュー'),
              onTap: () {
                Navigator.of(ctx).pop();
                _previewFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('ノートを作成'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createNoteFromFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('ファイルのURLをコピー'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(ClipboardData(text: file.url));
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('URLをコピーしました')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('フォルダに移動'),
              onTap: () {
                Navigator.of(ctx).pop();
                _moveSingleFile(file);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                '削除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteSingleFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveSingleFile(DriveFileModel file) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FolderPickerSheet(
        currentFolderId: _currentFolderId,
        onFolderSelected: (selectedFolderId) async {
          Navigator.of(ctx).pop();
          final api = ref.read(misskeyApiProvider);
          if (api == null) return;
          try {
            await api.moveFile(file.id, folderId: selectedFolderId);
            _load();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('移動に失敗しました: $e')));
          }
        },
      ),
    );
  }

  Future<void> _deleteSingleFile(DriveFileModel file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ファイルの削除'),
        content: Text('「${file.name}」を削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteFile(file.id);
      setState(() => _files.remove(file));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }

  void _confirmSelection() {
    final selected = _files.where((f) => _selectedIds.contains(f.id)).toList();
    context.pop(selected);
  }

  Future<void> _moveSelectedFiles() async {
    final ids = Set<String>.from(_selectedIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FolderPickerSheet(
        currentFolderId: _currentFolderId,
        onFolderSelected: (selectedFolderId) async {
          Navigator.of(ctx).pop();
          final api = ref.read(misskeyApiProvider);
          if (api == null) return;
          try {
            await Future.wait(
              ids.map((id) => api.moveFile(id, folderId: selectedFolderId)),
            );
            _exitManagingMode();
            _load();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('移動に失敗しました: $e')));
          }
        },
      ),
    );
  }

  Future<void> _deleteSelectedFiles() async {
    final ids = Set<String>.from(_selectedIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ファイルの削除'),
        content: ids.length == 1
            ? Text(
                '「${_files.firstWhere((f) => f.id == ids.first).name}」を削除しますか？\nこの操作は取り消せません。',
              )
            : Text('選択した${ids.length}件のファイルを削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await Future.wait(ids.map((id) => api.deleteFile(id)));
      setState(() => _files.removeWhere((f) => ids.contains(f.id)));
      _exitManagingMode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ファイルの選択に失敗しました')));
      return;
    }
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      setState(() => _isUploading = true);
      final file = File(path);
      final name = result.files.single.name;
      await api.uploadFile(file, name: name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('アップロードしました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('アップロードに失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = _breadcrumbs.length == 1;
    return PopScope(
      canPop: isRoot && !_managingMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_managingMode) {
            _exitManagingMode();
          } else {
            _navigateToBreadcrumb(_breadcrumbs.length - 2);
          }
        }
      },
      child: Scaffold(
        appBar: _managingMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitManagingMode,
                ),
                title: Text('${_selectedIds.length}件選択中'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_outlined),
                    tooltip: 'フォルダに移動',
                    onPressed: _selectedIds.isNotEmpty
                        ? _moveSelectedFiles
                        : null,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: _selectedIds.isNotEmpty
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    tooltip: '削除',
                    onPressed: _selectedIds.isNotEmpty
                        ? _deleteSelectedFiles
                        : null,
                  ),
                ],
              )
            : AppBar(
                title: _buildBreadcrumb(context),
                leading: isRoot
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () =>
                            _navigateToBreadcrumb(_breadcrumbs.length - 2),
                      ),
                actions: [
                  if (widget.selectionMode)
                    TextButton(
                      onPressed: _selectedIds.isNotEmpty
                          ? _confirmSelection
                          : null,
                      child: Text(
                        _selectedIds.isEmpty
                            ? '確定'
                            : '確定 (${_selectedIds.length})',
                      ),
                    ),
                ],
              ),
        floatingActionButton: (!widget.selectionMode && !_managingMode)
            ? FloatingActionButton.extended(
                heroTag: 'driveAddFile',
                onPressed: _isUploading ? null : _pickAndUploadFile,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('ファイル追加'),
              )
            : null,
        body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    if (_breadcrumbs.length == 1) return const Text('ドライブ');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < _breadcrumbs.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 16),
            GestureDetector(
              onTap: () => _navigateToBreadcrumb(i),
              child: Text(
                _breadcrumbs[i].name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: i == _breadcrumbs.length - 1
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _folders.isEmpty && _files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text('読み込みに失敗しました'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }

    if (_isLoading && _folders.isEmpty && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLoading && _folders.isEmpty && _files.isEmpty) {
      return const Center(child: Text('ファイルがありません'));
    }

    final itemCount = _folders.length + _files.length + (_isLoading ? 1 : 0);

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // フォルダを先頭に表示
        if (index < _folders.length) {
          return _FolderTile(
            folder: _folders[index],
            onTap: () => _openFolder(_folders[index]),
          );
        }
        final fileIndex = index - _folders.length;
        if (fileIndex >= _files.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final file = _files[fileIndex];
        return _DriveFileTile(
          file: file,
          selectionMode: widget.selectionMode || _managingMode,
          isSelected: _selectedIds.contains(file.id),
          onTap: () => _onFileTap(file),
          onLongPress: (widget.selectionMode || _managingMode)
              ? null
              : () => _enterManagingMode(file),
          onMenuTap: (widget.selectionMode || _managingMode)
              ? null
              : () => _showFileMenu(file),
        );
      },
    );
  }
}

// ---- フォルダタイル ----
class _FolderTile extends StatelessWidget {
  final _DriveFolder folder;
  final VoidCallback onTap;

  const _FolderTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                folder.name,
                style: theme.textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveFileTile extends StatelessWidget {
  final DriveFileModel file;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenuTap;

  const _DriveFileTile({
    required this.file,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (file.isImage) {
      content = CachedNetworkImage(
        imageUrl: file.thumbnailUrl ?? file.url,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            Container(color: theme.colorScheme.surfaceContainerHighest),
        errorWidget: (_, _, _) =>
            Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
      );
    } else {
      content = Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                file.name,
                style: theme.textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(4), child: content),
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.white.withAlpha(204),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: theme.colorScheme.onPrimary,
                      )
                    : null,
              ),
            ),
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
            ),
          if (onMenuTap != null)
            Positioned(
              bottom: 2,
              right: 2,
              child: GestureDetector(
                onTap: onMenuTap,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- フォルダ選択ボトムシート ----

class _FolderPickerSheet extends ConsumerStatefulWidget {
  final String? currentFolderId;
  final void Function(String? folderId) onFolderSelected;

  const _FolderPickerSheet({
    required this.currentFolderId,
    required this.onFolderSelected,
  });

  @override
  ConsumerState<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<_FolderPickerSheet> {
  final List<({String? id, String name})> _breadcrumbs = [
    (id: null, name: 'ドライブ'),
  ];
  List<_DriveFolder> _folders = [];
  bool _isLoading = true;
  String? _error;

  String? get _currentFolderId => _breadcrumbs.last.id;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final maps = await api.getDriveFolders(folderId: _currentFolderId);
      setState(() {
        _folders = maps.map(_DriveFolder.fromJson).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openFolder(_DriveFolder folder) {
    setState(() => _breadcrumbs.add((id: folder.id, name: folder.name)));
    _loadFolders();
  }

  void _navigateTo(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() => _breadcrumbs.removeRange(index + 1, _breadcrumbs.length));
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_breadcrumbs.length > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _navigateTo(_breadcrumbs.length - 2),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < _breadcrumbs.length; i++) ...[
                            if (i > 0)
                              const Icon(Icons.chevron_right, size: 16),
                            GestureDetector(
                              onTap: () => _navigateTo(i),
                              child: Text(
                                _breadcrumbs[i].name,
                                style: TextStyle(
                                  fontWeight: i == _breadcrumbs.length - 1
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 「ここに移動」ボタン（現在フォルダと同じなら無効）
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: Text(
                _currentFolderId == null
                    ? 'ルートに移動'
                    : '「${_breadcrumbs.last.name}」に移動',
              ),
              enabled: _currentFolderId != widget.currentFolderId,
              onTap: _currentFolderId != widget.currentFolderId
                  ? () => widget.onFolderSelected(_currentFolderId)
                  : null,
              tileColor: _currentFolderId != widget.currentFolderId
                  ? theme.colorScheme.primaryContainer.withAlpha(80)
                  : null,
            ),
            const Divider(height: 1),
            // フォルダ一覧
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('読み込みに失敗: $_error'))
                  : _folders.isEmpty
                  ? const Center(child: Text('サブフォルダがありません'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _folders.length,
                      itemBuilder: (_, i) {
                        final f = _folders[i];
                        return ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(f.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openFolder(f),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---- 画像プレビュー画面 ----

class _DriveImagePreviewScreen extends StatelessWidget {
  final DriveFileModel file;

  const _DriveImagePreviewScreen({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(file.name, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white),
            tooltip: 'ブラウザで開く',
            onPressed: () => launchUrl(
              Uri.parse(file.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 8,
          child: CachedNetworkImage(
            imageUrl: file.url,
            placeholder: (_, _) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
