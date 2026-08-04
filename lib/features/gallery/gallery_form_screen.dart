import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/image_compression_level.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/image_compression_service.dart';
import '../../data/models/gallery_post_model.dart';
import '../../data/models/note_model.dart' as note_models;
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/widgets/api_error_snack_bar.dart';

const _maxImages = 32;
const _uuid = Uuid();

/// アップロード待ち・アップロード済みの1枚を表す作業中モデル。
///
/// - 既存投稿の画像 / ドライブから選択した画像は [fileId] が最初から確定している。
/// - 端末から選択した画像は [localFile] を持ち、選択直後にバックグラウンドで
///   アップロードを開始し、完了すると [fileId] が入る。
class _StagedImage {
  final String key;
  String? fileId;
  final String? previewUrl;
  final File? localFile;
  bool uploadFailed;

  _StagedImage({
    required this.key,
    this.fileId,
    this.previewUrl,
    this.localFile,
  }) : uploadFailed = false;

  bool get isUploading => localFile != null && fileId == null && !uploadFailed;
}

/// ギャラリー投稿の作成・編集フォーム。
///
/// [post] が非 null なら編集（`gallery/posts/update`）、null なら新規作成
/// （`gallery/posts/create`）として動作する。
/// [postId] は [post] が渡されなかった場合（例: 復元されたルート）のフォールバックで、
/// 指定されていれば起動時に取得を試みる。
class GalleryFormScreen extends ConsumerStatefulWidget {
  final GalleryPostModel? post;
  final String? postId;

  const GalleryFormScreen({super.key, this.post, this.postId});

  @override
  ConsumerState<GalleryFormScreen> createState() => _GalleryFormScreenState();
}

class _GalleryFormScreenState extends ConsumerState<GalleryFormScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSensitive = false;
  final List<_StagedImage> _images = [];
  bool _isSaving = false;
  bool _isLoadingPost = false;
  String? _loadError;
  GalleryPostModel? _post;

  bool get _isEditing => _post != null;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    if (_post != null) {
      _applyPost(_post!);
    } else if (widget.postId != null) {
      _loadPost(widget.postId!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _applyPost(GalleryPostModel post) {
    _titleController.text = post.title;
    _descController.text = post.description ?? '';
    _isSensitive = post.isSensitive;
    _images
      ..clear()
      ..addAll(
        post.files.map(
          (f) => _StagedImage(
            key: f.id,
            fileId: f.id,
            previewUrl: f.thumbnailUrl ?? f.url,
          ),
        ),
      );
  }

  Future<void> _loadPost(String postId) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    setState(() => _isLoadingPost = true);
    try {
      final post = await api.getGalleryPost(postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _applyPost(post);
        _isLoadingPost = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPost = false;
        _loadError = '投稿を読み込めませんでした';
      });
    }
  }

  bool get _isUploadingAny => _images.any((i) => i.isUploading);

  Future<void> _showAddImageSheet() async {
    if (_images.length >= _maxImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('画像は最大32枚までです')));
      return;
    }
    final source = await showModalBottomSheet<_ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('ドライブから選択'),
              onTap: () => Navigator.pop(ctx, _ImageSource.drive),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('端末から選択'),
              onTap: () => Navigator.pop(ctx, _ImageSource.device),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == _ImageSource.drive) {
      await _pickFromDrive();
    } else {
      await _pickFromDevice();
    }
  }

  Future<void> _pickFromDrive() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0 || !mounted) return;
    final selected = await context.push<List<note_models.DriveFileModel>>(
      '/drive',
      extra: {'selectionMode': true, 'maxSelection': remaining},
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() {
      var skippedDuplicate = false;
      for (final f in selected) {
        if (_images.length >= _maxImages) break;
        if (_images.any((i) => i.fileId == f.id)) {
          skippedDuplicate = true;
          continue;
        }
        _images.add(
          _StagedImage(
            key: f.id,
            fileId: f.id,
            previewUrl: f.thumbnailUrl ?? f.url,
          ),
        );
      }
      if (skippedDuplicate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('すでに追加されている画像は除外しました')),
          );
        });
      }
    });
  }

  Future<void> _pickFromDevice() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0 || !mounted) return;
    final picker = ImagePicker();
    List<XFile> files;
    try {
      files = await picker.pickMultiImage(limit: remaining);
    } catch (_) {
      return;
    }
    if (files.isEmpty || !mounted) return;
    final level = ref.read(settingsProvider).defaultImageCompressionLevel;
    final toAdd = files.take(remaining).toList();
    final staged = [
      for (final xfile in toAdd)
        _StagedImage(key: _uuid.v4(), localFile: File(xfile.path)),
    ];
    setState(() => _images.addAll(staged));
    for (var i = 0; i < staged.length; i++) {
      _uploadLocalImage(staged[i], toAdd[i].name, level);
    }
  }

  Future<void> _uploadLocalImage(
    _StagedImage staged,
    String fileName,
    ImageCompressionLevel level,
  ) async {
    final api = ref.read(misskeyApiProvider);
    final file = staged.localFile;
    if (api == null || file == null) return;
    try {
      var uploadTarget = file;
      if (level != ImageCompressionLevel.none &&
          ImageCompressionService.isCompressible(file.path)) {
        uploadTarget = await ImageCompressionService.compress(
          file: file,
          level: level,
        );
      }
      final id = await api.uploadFile(uploadTarget, name: fileName);
      if (!mounted) return;
      // 既に他の画像として同じファイルIDが追加されていたら重複を避けて削除する
      if (_images.any((i) => i.key != staged.key && i.fileId == id)) {
        setState(() => _images.removeWhere((i) => i.key == staged.key));
        return;
      }
      setState(() => staged.fileId = id);
    } catch (_) {
      if (!mounted) return;
      setState(() => staged.uploadFailed = true);
    }
  }

  void _retryUpload(_StagedImage staged) {
    final level = ref.read(settingsProvider).defaultImageCompressionLevel;
    setState(() => staged.uploadFailed = false);
    final name = staged.localFile?.path.split(RegExp(r'[\\/]')).last ?? 'image';
    _uploadLocalImage(staged, name, level);
  }

  void _removeImage(_StagedImage image) {
    setState(() => _images.removeWhere((i) => i.key == image.key));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
      return;
    }
    final fileIds = _images
        .where((i) => i.fileId != null)
        .map((i) => i.fileId!)
        .toList();
    if (fileIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('画像を1枚以上追加してください')));
      return;
    }
    if (_isUploadingAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画像をアップロード中です。完了までお待ちください')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _isSaving = false);
      return;
    }
    final description = _descController.text.trim();

    try {
      final GalleryPostModel result;
      if (_isEditing) {
        result = await api.updateGalleryPost(
          postId: _post!.id,
          title: title,
          fileIds: fileIds,
          description: description.isEmpty ? null : description,
          clearDescription: description.isEmpty,
          isSensitive: _isSensitive,
        );
      } else {
        result = await api.createGalleryPost(
          title: title,
          fileIds: fileIds,
          description: description.isEmpty ? null : description,
          isSensitive: _isSensitive,
        );
      }
      if (mounted) context.pop(result);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        // gallery/posts/create はレート制限が厳しい（20回/時）ため、
        // ここでの自動リトライは行わずユーザー操作に委ねる。
        showApiErrorSnackBar(
          context,
          e,
          fallback: _isEditing ? '更新に失敗しました' : '投稿に失敗しました',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPost) {
      return Scaffold(
        appBar: AppBar(title: const Text('読み込み中')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ギャラリー')),
        body: Center(child: Text(_loadError!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '投稿を編集' : '新しい投稿'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isEditing ? '保存' : '投稿'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('画像 (${_images.length}/$_maxImages)',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _buildImageRow(),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                hintText: '作品のタイトルを入力',
                border: OutlineInputBorder(),
              ),
              maxLength: 256,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: '説明（任意）',
                hintText: '説明を入力。文中の #タグ は自動的にタグとして扱われます',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              minLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.tag,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '説明文にハッシュタグを書くと、投稿のタグとして表示されます',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _isSensitive,
              onChanged: (v) => setState(() => _isSensitive = v),
              title: const Text('センシティブな内容として投稿する'),
              subtitle: const Text('投稿全体にぼかしがかかり、タップで表示されるようになります'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_off_outlined),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildImageRow() {
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AddImageButton(onTap: _showAddImageSheet),
          const SizedBox(width: 8),
          Expanded(
            child: _images.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '画像を追加してください（1〜32枚）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: true,
                    itemCount: _images.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final img = _images[index];
                      return Padding(
                        key: ValueKey(img.key),
                        padding: const EdgeInsets.only(right: 8),
                        child: _ImageTile(
                          image: img,
                          onRemove: () => _removeImage(img),
                          onRetry: () => _retryUpload(img),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _ImageSource { drive, device }

class _AddImageButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddImageButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Icon(Icons.add_photo_alternate_outlined, color: theme.colorScheme.primary),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final _StagedImage image;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  const _ImageTile({
    required this.image,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (image.localFile != null) {
      content = Image.file(image.localFile!, fit: BoxFit.cover);
    } else if (image.previewUrl != null) {
      content = CachedNetworkImage(
        cacheManager: AppCacheManager(),
        imageUrl: image.previewUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
        ),
      );
    } else {
      content = Container(color: theme.colorScheme.surfaceContainerHighest);
    }

    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: content),
          if (image.isUploading)
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (image.uploadFailed)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, color: Colors.white, size: 20),
                      Text(
                        '再試行',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
