import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/utils/download_helper.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/drive_folder_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/media_player_screen.dart';
import 'file_notes_screen.dart';
import '../../shared/utils/format_utils.dart';

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

  List<DriveFolderModel> _folders = [];
  List<DriveFileModel> _files = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();
  final Set<String> _selectedFileIds = {};
  final Set<String> _selectedFolderIds = {};
  bool _managingMode = false;
  String? _managingModeSourceFolderId;
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
    if (api == null) {
      setState(() {
        _error = 'ログインが必要です';
        _isLoading = false;
      });
      return;
    }
    try {
      final folderMaps = await api.getDriveFolders(folderId: _currentFolderId);
      final files = await api.getDriveFiles(
        limit: 40,
        folderId: _currentFolderId,
      );
      setState(() {
        _folders = folderMaps;
        _files = files;
        _hasMore = files.length >= 40;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = apiErrorMessage(e, fallback: 'ドライブを取得できませんでした');
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
      // catch 節でしか _isLoading を戻していないため、
      // ここで素通しすると以降の追加読み込みが止まる。
      if (api == null) {
        setState(() => _isLoading = false);
        return;
      }
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

  void _openFolder(DriveFolderModel folder) {
    setState(() {
      _breadcrumbs.add((id: folder.id, name: folder.name));
      if (!_managingMode) {
        _selectedFileIds.clear();
        _selectedFolderIds.clear();
      }
    });
    _load();
  }

  void _navigateToBreadcrumb(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      if (!_managingMode) {
        _selectedFileIds.clear();
        _selectedFolderIds.clear();
      }
    });
    _load();
  }

  void _onFileTap(DriveFileModel file) {
    if (widget.selectionMode) {
      setState(() {
        if (_selectedFileIds.contains(file.id)) {
          _selectedFileIds.remove(file.id);
        } else {
          if (_selectedFileIds.length >= widget.maxSelection) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('最大${widget.maxSelection}件まで選択できます'),
                duration: const Duration(seconds: 1),
              ),
            );
            return;
          }
          _selectedFileIds.add(file.id);
        }
      });
    } else if (_managingMode) {
      // 管理モード開始フォルダにいる場合のみ選択可能
      if (_currentFolderId == _managingModeSourceFolderId) {
        setState(() {
          if (_selectedFileIds.contains(file.id)) {
            _selectedFileIds.remove(file.id);
            if (_selectedFileIds.isEmpty && _selectedFolderIds.isEmpty) {
              _exitManagingMode();
            }
          } else {
            _selectedFileIds.add(file.id);
          }
        });
      }
    } else {
      _previewFile(file);
    }
  }

  void _enterManagingMode({DriveFileModel? file, DriveFolderModel? folder}) {
    setState(() {
      _managingMode = true;
      _managingModeSourceFolderId = _currentFolderId;
      if (file != null) _selectedFileIds.add(file.id);
      if (folder != null) _selectedFolderIds.add(folder.id);
    });
  }

  void _onFolderTap(DriveFolderModel folder) {
    _openFolder(folder);
  }

  void _toggleFolderSelection(DriveFolderModel folder) {
    setState(() {
      if (_selectedFolderIds.contains(folder.id)) {
        _selectedFolderIds.remove(folder.id);
        if (_selectedFileIds.isEmpty && _selectedFolderIds.isEmpty) {
          _exitManagingMode();
        }
      } else {
        _selectedFolderIds.add(folder.id);
      }
    });
  }

  void _exitManagingMode() {
    setState(() {
      _managingMode = false;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      _managingModeSourceFolderId = null;
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
              leading: const Icon(Icons.article_outlined),
              title: const Text('このファイルが添付されたノート'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DriveFileNotesScreen(file: file),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                file.isSensitive
                    ? Icons.visibility_outlined
                    : Icons.disabled_visible_outlined,
              ),
              title: Text(file.isSensitive ? 'センシティブ設定を解除' : 'センシティブとして設定'),
              onTap: () {
                Navigator.of(ctx).pop();
                _toggleFileSensitive(file);
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

  Future<void> _toggleFileSensitive(DriveFileModel file) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final newValue = !file.isSensitive;
    try {
      await api.updateFileSensitive(file.id, isSensitive: newValue);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e, fallback: '更新に失敗しました')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _moveSingleFile(DriveFileModel file) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
            showApiErrorSnackBar(context, e, fallback: '移動に失敗しました');
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
      showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
    }
  }

  void _confirmSelection() {
    final selected = _files
        .where((f) => _selectedFileIds.contains(f.id))
        .toList();
    context.pop(selected);
  }

  Future<void> _moveToCurrentFolder() async {
    final fileIds = Set<String>.from(_selectedFileIds);
    final folderIds = Set<String>.from(_selectedFolderIds);
    final targetFolderId = _currentFolderId;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await Future.wait([
        ...fileIds.map((id) => api.moveFile(id, folderId: targetFolderId)),
        ...folderIds.map((id) => api.moveFolder(id, parentId: targetFolderId)),
      ]);
      _exitManagingMode();
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: '移動に失敗しました');
    }
  }

  Future<void> _deleteSelected() async {
    final fileIds = Set<String>.from(_selectedFileIds);
    final folderIds = Set<String>.from(_selectedFolderIds);
    final totalCount = fileIds.length + folderIds.length;
    final String contentText;
    if (totalCount == 1) {
      if (fileIds.length == 1) {
        contentText =
            '「${_files.firstWhere((f) => f.id == fileIds.first).name}」を削除しますか？\nこの操作は取り消せません。';
      } else {
        contentText =
            '「${_folders.firstWhere((f) => f.id == folderIds.first).name}」を削除しますか？\nこの操作は取り消せません。';
      }
    } else {
      contentText = '選択した$totalCount件のアイテムを削除しますか？\nこの操作は取り消せません。';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除'),
        content: Text(contentText),
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
      await Future.wait([
        ...fileIds.map((id) => api.deleteFile(id)),
        ...folderIds.map((id) => api.deleteDriveFolder(id)),
      ]);
      setState(() {
        _files.removeWhere((f) => fileIds.contains(f.id));
        _folders.removeWhere((f) => folderIds.contains(f.id));
      });
      _exitManagingMode();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
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
      await api.uploadFile(file, name: name, folderId: _currentFolderId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('アップロードしました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: 'アップロードに失敗しました');
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
            if (_currentFolderId != _managingModeSourceFolderId) {
              // 移動先フォルダにいる場合は前のフォルダへ戻る
              _navigateToBreadcrumb(_breadcrumbs.length - 2);
            } else {
              // 管理モード開始フォルダにいる場合は管理モードを終了
              _exitManagingMode();
            }
          } else {
            _navigateToBreadcrumb(_breadcrumbs.length - 2);
          }
        }
      },
      child: Scaffold(
        appBar: _managingMode
            ? AppBar(
                leadingWidth: _breadcrumbs.length > 1 ? 48 : 0,
                leading: _breadcrumbs.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: '上の階層へ',
                        onPressed: () =>
                            _navigateToBreadcrumb(_breadcrumbs.length - 2),
                      )
                    : const SizedBox.shrink(),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${_selectedFileIds.length + _selectedFolderIds.length}件選択中',
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: '選択を解除',
                      child: GestureDetector(
                        onTap: _exitManagingMode,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.drive_file_move),
                    tooltip: 'このフォルダに移動',
                    onPressed:
                        (_selectedFileIds.isNotEmpty ||
                                _selectedFolderIds.isNotEmpty) &&
                            _currentFolderId != _managingModeSourceFolderId
                        ? _moveToCurrentFolder
                        : null,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color:
                          (_selectedFileIds.isNotEmpty ||
                              _selectedFolderIds.isNotEmpty)
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    tooltip: '削除',
                    onPressed:
                        (_selectedFileIds.isNotEmpty ||
                            _selectedFolderIds.isNotEmpty)
                        ? _deleteSelected
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
                  if (!widget.selectionMode)
                    IconButton(
                      icon: const Icon(Icons.pie_chart_outline),
                      tooltip: 'ドライブの使用状況',
                      onPressed: _showDriveUsage,
                    ),
                  if (!widget.selectionMode)
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      tooltip: 'フォルダ作成',
                      onPressed: _showCreateFolderDialog,
                    ),
                  if (widget.selectionMode)
                    TextButton(
                      onPressed: _selectedFileIds.isNotEmpty
                          ? _confirmSelection
                          : null,
                      child: Text(
                        _selectedFileIds.isEmpty
                            ? '確定'
                            : '確定 (${_selectedFileIds.length})',
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
      return Center(child: Text('読み込みに失敗: $_error'));
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
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        4,
        4,
        4,
        4 + MediaQuery.of(context).padding.bottom,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // フォルダを先頭に表示
        if (index < _folders.length) {
          final isOnSourceFolder =
              _currentFolderId == _managingModeSourceFolderId;
          final isFolderSelected = _selectedFolderIds.contains(
            _folders[index].id,
          );
          return _FolderTile(
            folder: _folders[index],
            selectionMode: _managingMode && isOnSourceFolder,
            isSelected: isFolderSelected,
            onTap: () {
              if (_managingMode && isOnSourceFolder && isFolderSelected) {
                _toggleFolderSelection(_folders[index]);
              } else {
                _onFolderTap(_folders[index]);
              }
            },
            onLongPress: _managingMode
                ? null
                : () => _enterManagingMode(folder: _folders[index]),
            onMenuTap: _managingMode
                ? null
                : () => _showFolderMenu(_folders[index]),
            onSelectToggle: (_managingMode && isOnSourceFolder)
                ? () => _toggleFolderSelection(_folders[index])
                : null,
          );
        }
        final fileIndex = index - _folders.length;
        if (fileIndex >= _files.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final file = _files[fileIndex];
        return _DriveFileTile(
          file: file,
          selectionMode:
              widget.selectionMode ||
              (_managingMode &&
                  _currentFolderId == _managingModeSourceFolderId),
          isSelected: _selectedFileIds.contains(file.id),
          onTap: () => _onFileTap(file),
          onLongPress: (widget.selectionMode || _managingMode)
              ? null
              : () => _enterManagingMode(file: file),
          onMenuTap: (widget.selectionMode || _managingMode)
              ? null
              : () => _showFileMenu(file),
        );
      },
    );
  }

  void _showDriveUsage() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _DriveUsageSheet(),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('フォルダの作成'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'フォルダ名'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォルダ名を入力してください')));
      return;
    }
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.createDriveFolder(name: name, parentId: _currentFolderId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォルダを作成しました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: 'フォルダを作成できませんでした');
    }
  }

  Future<void> _showFolderMenu(DriveFolderModel folder) async {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('開く'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('名前を変更'),
              onTap: () {
                Navigator.of(ctx).pop();
                _renameFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('フォルダに移動'),
              onTap: () {
                Navigator.of(ctx).pop();
                _moveSingleFolder(folder);
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
                _deleteFolder(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveSingleFolder(DriveFolderModel folder) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _FolderPickerSheet(
        currentFolderId: _currentFolderId,
        excludeFolderId: folder.id,
        onFolderSelected: (selectedFolderId) async {
          Navigator.of(ctx).pop();
          final api = ref.read(misskeyApiProvider);
          if (api == null) return;
          try {
            await api.moveFolder(folder.id, parentId: selectedFolderId);
            _load();
          } catch (e) {
            if (!mounted) return;
            showApiErrorSnackBar(context, e, fallback: '移動に失敗しました');
          }
        },
      ),
    );
  }

  Future<void> _renameFolder(DriveFolderModel folder) async {
    final controller = TextEditingController(text: folder.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('フォルダ名の変更'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新しいフォルダ名'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('変更'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォルダ名を入力してください')));
      return;
    }
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.updateDriveFolder(folder.id, name: newName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォルダ名を変更しました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: '変更に失敗しました');
    }
  }

  Future<void> _deleteFolder(DriveFolderModel folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('フォルダの削除'),
        content: Text('「${folder.name}」を削除しますか？\nこの操作は取り消せません。'),
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
      await api.deleteDriveFolder(folder.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォルダを削除しました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
    }
  }
}

// ---- フォルダタイル ----
class _FolderTile extends StatelessWidget {
  final DriveFolderModel folder;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenuTap;
  final VoidCallback? onSelectToggle;

  const _FolderTile({
    required this.folder,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.onMenuTap,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
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
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onSelectToggle,
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
            ),
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
            ),
          // 選択中は移動不可を示す半透明オーバーレイ
          if (selectionMode && isSelected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: theme.colorScheme.primary.withAlpha(30),
                ),
                child: const Center(
                  child: Icon(Icons.block, size: 18, color: Colors.white54),
                ),
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
        cacheManager: AppCacheManager(),
        imageUrl: file.thumbnailUrl ?? file.url,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            Container(color: theme.colorScheme.surfaceContainerHighest),
        errorWidget: (_, _, _) =>
            Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
      );
    } else if (file.isVideo) {
      // 動画はサムネイルがあれば表示、なければ黒背景にする
      content = file.thumbnailUrl != null
          ? CachedNetworkImage(
              cacheManager: AppCacheManager(),
              imageUrl: file.thumbnailUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: Colors.black),
              errorWidget: (_, _, _) => Container(color: Colors.black),
            )
          : Container(color: Colors.black);
    } else if (file.isAudio) {
      // 音声ファイルはファイルアイコンの代わりに♪を表示
      content = Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 28, color: theme.colorScheme.primary),
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
          // 動画の場合は再生アイコンをオーバーレイ
          if (file.isVideo)
            const Center(
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.black54,
                child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
              ),
            ),
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
          if (file.isSensitive)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.disabled_visible,
                  size: 12,
                  color: theme.colorScheme.onError,
                ),
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
  final String? excludeFolderId;
  final void Function(String? folderId) onFolderSelected;

  const _FolderPickerSheet({
    required this.currentFolderId,
    this.excludeFolderId,
    required this.onFolderSelected,
  });

  @override
  ConsumerState<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<_FolderPickerSheet> {
  final List<({String? id, String name})> _breadcrumbs = [
    (id: null, name: 'ドライブ'),
  ];
  List<DriveFolderModel> _folders = [];
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
    if (api == null) {
      setState(() {
        _error = 'ログインが必要です';
        _isLoading = false;
      });
      return;
    }
    try {
      final maps = await api.getDriveFolders(folderId: _currentFolderId);
      setState(() {
        _folders = maps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = apiErrorMessage(e, fallback: 'フォルダを取得できませんでした');
        _isLoading = false;
      });
    }
  }

  void _openFolder(DriveFolderModel folder) {
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
                  : Builder(
                      builder: (context) {
                        final visibleFolders = _folders
                            .where((f) => f.id != widget.excludeFolderId)
                            .toList();
                        if (visibleFolders.isEmpty) {
                          return const Center(child: Text('サブフォルダがありません'));
                        }
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: visibleFolders.length,
                          itemBuilder: (_, i) {
                            final f = visibleFolders[i];
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

// ---- ドライブ使用状況シート ----

class _DriveUsageSheet extends ConsumerStatefulWidget {
  const _DriveUsageSheet();

  @override
  ConsumerState<_DriveUsageSheet> createState() => _DriveUsageSheetState();
}

class _DriveUsageSheetState extends ConsumerState<_DriveUsageSheet> {
  Future<({int capacity, int usage})>? _future;

  @override
  void initState() {
    super.initState();
    final api = ref.read(misskeyApiProvider);
    _future = api?.getDriveInfo();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('ドライブの使用状況', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 24),
            if (_future == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('アカウント情報を取得できません')),
              )
            else
              FutureBuilder<({int capacity, int usage})>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('使用状況の取得に失敗しました')),
                    );
                  }
                  return _buildUsage(context, snapshot.data!);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsage(BuildContext context, ({int capacity, int usage}) info) {
    final theme = Theme.of(context);
    final capacity = info.capacity;
    final usage = info.usage;
    final ratio = capacity > 0 ? (usage / capacity).clamp(0.0, 1.0) : 0.0;
    final remaining = (capacity - usage).clamp(0, capacity);
    final percent = (ratio * 100);

    // 使用率が高いほど警告色に変化させる
    final Color usedColor = ratio >= 0.9
        ? theme.colorScheme.error
        : ratio >= 0.7
        ? Colors.orange
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ドーナツグラフ
        SizedBox(
          height: 180,
          child: Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: _DonutChartPainter(
                  ratio: ratio,
                  usedColor: usedColor,
                  trackColor: theme.colorScheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: usedColor,
                        ),
                      ),
                      Text(
                        '使用中',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _usageRow(
          context,
          color: usedColor,
          label: '使用量',
          value: formatBytes(usage),
        ),
        const SizedBox(height: 12),
        _usageRow(
          context,
          color: theme.colorScheme.surfaceContainerHighest,
          label: '空き容量',
          value: formatBytes(remaining),
        ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '総容量',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              formatBytes(capacity),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _usageRow(
    BuildContext context, {
    required Color color,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: theme.textTheme.bodyLarge),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// ドライブ使用状況を表すドーナツ型グラフのペインター。
class _DonutChartPainter extends CustomPainter {
  final double ratio;
  final Color usedColor;
  final Color trackColor;

  _DonutChartPainter({
    required this.ratio,
    required this.usedColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 20.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (ratio > 0) {
      final usedPaint = Paint()
        ..color = usedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      const startAngle = -1.5707963267948966; // -90度（真上）
      final sweepAngle = 6.283185307179586 * ratio; // 2π * ratio
      canvas.drawArc(rect, startAngle, sweepAngle, false, usedPaint);
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.usedColor != usedColor ||
        oldDelegate.trackColor != trackColor;
  }
}

// ---- 画像プレビュー画面 ----

class _DriveImagePreviewScreen extends StatefulWidget {
  final DriveFileModel file;

  const _DriveImagePreviewScreen({required this.file});

  @override
  State<_DriveImagePreviewScreen> createState() =>
      _DriveImagePreviewScreenState();
}

class _DriveImagePreviewScreenState extends State<_DriveImagePreviewScreen>
    with SingleTickerProviderStateMixin {
  late TransformationController _controller;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final anim = _animation;
          if (anim != null) {
            _controller.value = anim.value;
          }
        });
    _controller.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _handleDoubleTap() {
    final controller = _controller;
    final currentScale = controller.value.getMaxScaleOnAxis();
    final double targetScale = currentScale > 1.0 ? 1.0 : 2.5;
    final begin = controller.value;

    final focal = _doubleTapDetails?.localPosition ?? Offset.zero;

    final tx = -focal.dx * (targetScale - 1);
    final ty = -focal.dy * (targetScale - 1);

    final end = Matrix4.identity()..translateByDouble(tx, ty, 0.0, 1.0);
    end.multiply(Matrix4.diagonal3Values(targetScale, targetScale, 1.0));

    _animation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward(from: 0);

    _doubleTapDetails = null;
  }

  Future<void> _downloadFile() async {
    final url = widget.file.url;
    final filename = widget.file.name;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('ダウンロードを開始します...')));
    try {
      await DownloadHelper.downloadToPublicDownloads(
        url: url,
        fileName: filename,
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('「$filename」をDownloadフォルダに保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('ダウンロードに失敗しました')));
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupBg = theme.colorScheme.surface;
    final popupOn = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.file.name,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          PopupMenuButton<String>(
            color: popupBg,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 8,
            offset: const Offset(0, 8),
            onSelected: (v) {
              if (v == 'download') _downloadFile();
              if (v == 'open') {
                launchUrl(
                  Uri.parse(widget.file.url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ダウンロード',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ブラウザで開く',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: SizedBox.expand(
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 0.5,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(48),
              child: Center(
                child: CachedNetworkImage(
                  cacheManager: AppCacheManager(),
                  imageUrl: widget.file.url,
                  fit: BoxFit.contain,
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
          ),
        ),
      ),
    );
  }
}
