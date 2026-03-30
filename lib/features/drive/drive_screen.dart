import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';

/// ドライブフォルダの簡易モデル
class _DriveFolder {
  final String id;
  final String name;
  const _DriveFolder({required this.id, required this.name});

  factory _DriveFolder.fromJson(Map<String, dynamic> json) => _DriveFolder(
    id: json['id'] as String,
    name: json['name'] as String,
  );
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
    });
    _load();
  }

  void _navigateToBreadcrumb(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      _selectedIds.clear();
    });
    _load();
  }

  void _onFileTap(DriveFileModel file) {
    if (!widget.selectionMode) return;
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
  }

  void _confirmSelection() {
    final selected = _files.where((f) => _selectedIds.contains(f.id)).toList();
    context.pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = _breadcrumbs.length == 1;
    return PopScope(
      canPop: isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isRoot) {
          _navigateToBreadcrumb(_breadcrumbs.length - 2);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _buildBreadcrumb(context),
          leading: isRoot
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigateToBreadcrumb(_breadcrumbs.length - 2),
                ),
          actions: [
            if (widget.selectionMode)
              TextButton(
                onPressed: _selectedIds.isNotEmpty ? _confirmSelection : null,
                child: Text(
                  _selectedIds.isEmpty ? '確定' : '確定 (${_selectedIds.length})',
                ),
              ),
          ],
        ),
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
            if (i > 0)
              const Icon(Icons.chevron_right, size: 16),
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
          selectionMode: widget.selectionMode,
          isSelected: _selectedIds.contains(file.id),
          onTap: () => _onFileTap(file),
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

  const _DriveFileTile({
    required this.file,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (file.isImage) {
      content = CachedNetworkImage(
        imageUrl: file.thumbnailUrl ?? file.url,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            Container(color: theme.colorScheme.surfaceContainerHighest),
        errorWidget: (_, __, ___) =>
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
        ],
      ),
    );
  }
}
