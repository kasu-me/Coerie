import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';

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
  final List<DriveFileModel> _files = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadMore();
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
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(misskeyApiProvider);
      if (api == null) return;
      final untilId = _files.isNotEmpty ? _files.last.id : null;
      final newFiles = await api.getDriveFiles(limit: 40, untilId: untilId);
      setState(() {
        _files.addAll(newFiles);
        _hasMore = newFiles.length >= 40;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _files.clear();
      _hasMore = true;
      _error = null;
      _selectedIds.clear();
    });
    await _loadMore();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('ドライブ'),
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
      body: RefreshIndicator(onRefresh: _refresh, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _files.isEmpty) {
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
            FilledButton(onPressed: _refresh, child: const Text('再試行')),
          ],
        ),
      );
    }

    if (_files.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_files.isEmpty) {
      return const Center(child: Text('ファイルがありません'));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _files.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _files.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final file = _files[index];
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
