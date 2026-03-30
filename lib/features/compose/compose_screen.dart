import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../draft/draft_provider.dart';
import 'emoji_picker_sheet.dart';

sealed class _AttachedMedia {}

final class _LocalMedia extends _AttachedMedia {
  final XFile file;
  _LocalMedia(this.file);
}

final class _DriveMedia extends _AttachedMedia {
  final DriveFileModel driveFile;
  _DriveMedia(this.driveFile);
}

enum _MediaSource { gallery, camera, drive }

class ComposeScreen extends ConsumerStatefulWidget {
  final String? draftId;
  final String? replyId;
  final NoteModel? replyToNote;

  const ComposeScreen({
    super.key,
    this.draftId,
    this.replyId,
    this.replyToNote,
  });

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _textController;
  late String _visibility;
  String? _currentDraftId;
  final List<_AttachedMedia> _attachedMedia = [];
  bool _isPosting = false;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _currentDraftId = widget.draftId;
    // 保存済みのデフォルト公開範囲で初期化
    _visibility = ref.read(settingsProvider).defaultVisibility;

    if (widget.draftId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final draft = ref
            .read(draftProvider.notifier)
            .getDraft(widget.draftId!);
        if (draft != null) {
          _textController.text = draft.text;
          setState(() => _visibility = draft.visibility);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _charCount => _textController.text.length;
  int get _charLimit => AppConstants.defaultNoteLimit;
  bool get _isOverLimit => _charCount > _charLimit;

  Future<void> _saveDraft() async {
    if (_textController.text.trim().isEmpty) {
      context.pop();
      return;
    }
    _currentDraftId = await ref
        .read(draftProvider.notifier)
        .saveDraft(
          text: _textController.text,
          visibility: _visibility,
          existingId: _currentDraftId,
        );
    if (mounted) context.pop();
  }

  Future<void> _pickMedia() async {
    if (_attachedMedia.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添付できるファイルは最大4件です')));
      return;
    }

    final source = await showModalBottomSheet<_MediaSource>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('ギャラリーから選択'),
            onTap: () => Navigator.pop(context, _MediaSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('カメラで撮影'),
            onTap: () => Navigator.pop(context, _MediaSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Misskeyドライブから選択'),
            onTap: () => Navigator.pop(context, _MediaSource.drive),
          ),
        ],
      ),
    );
    if (source == null) return;

    if (source == _MediaSource.drive) {
      final remaining = 4 - _attachedMedia.length;
      if (!mounted) return;
      final selected = await context.push<List<DriveFileModel>>(
        '/drive',
        extra: {'selectionMode': true, 'maxSelection': remaining},
      );
      if (selected != null && selected.isNotEmpty && mounted) {
        setState(() {
          for (final f in selected) {
            _attachedMedia.add(_DriveMedia(f));
          }
        });
      }
      return;
    }

    final picker = ImagePicker();
    if (source == _MediaSource.gallery) {
      final remaining = 4 - _attachedMedia.length;
      final files = await picker.pickMultiImage(limit: remaining);
      if (files.isNotEmpty) {
        setState(() => _attachedMedia.addAll(files.map(_LocalMedia.new)));
      }
    } else {
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file != null) {
        setState(() => _attachedMedia.add(_LocalMedia(file)));
      }
    }
  }

  void _removeMedia(int index) {
    setState(() => _attachedMedia.removeAt(index));
  }

  Future<void> _post() async {
    if (_textController.text.trim().isEmpty && _attachedMedia.isEmpty) return;
    if (_isOverLimit || _isPosting) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    setState(() => _isPosting = true);

    try {
      // メディアを先にアップロード（端末のファイルのみアップロード、ドライブはIDをそのまま使用）
      final fileIds = <String>[];
      if (_attachedMedia.isNotEmpty) {
        setState(() => _isUploadingMedia = true);
        for (final media in _attachedMedia) {
          if (media is _LocalMedia) {
            final id = await api.uploadFile(File(media.file.path));
            fileIds.add(id);
          } else if (media is _DriveMedia) {
            fileIds.add(media.driveFile.id);
          }
        }
        setState(() => _isUploadingMedia = false);
      }

      await api.createNote(
        text: _textController.text.trim().isEmpty ? null : _textController.text,
        visibility: _visibility,
        fileIds: fileIds,
        replyId: widget.replyId,
      );

      if (_currentDraftId != null) {
        await ref.read(draftProvider.notifier).deleteDraft(_currentDraftId!);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _isUploadingMedia = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '投稿に失敗しました: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _showVisibilityPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '公開範囲',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...AppConstants.visibilityLabels.entries.map(
            (e) => ListTile(
              leading: Icon(_visibilityIcon(e.key)),
              title: Text(e.value),
              trailing: _visibility == e.key
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() => _visibility = e.key);
                ref.read(settingsProvider.notifier).setDefaultVisibility(e.key);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context, WidgetRef ref) {
    final accounts = ref.read(accountProvider);
    if (accounts.length <= 1) return; // 1アカウントのみなら何もしない
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '投稿アカウントを切り替え',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...accounts.map(
            (a) => ListTile(
              leading: a.avatarUrl != null
                  ? CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(a.avatarUrl!),
                    )
                  : const CircleAvatar(child: Icon(Icons.person)),
              title: Text(a.name),
              subtitle: Text(a.acct),
              trailing: a.isActive
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                ref.read(accountProvider.notifier).switchAccount(a.id);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: () => context.pop(),
          child: const Text('キャンセル'),
        ),
        leadingWidth: 90,
        actions: [
          TextButton.icon(
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('下書き'),
          ),
        ],
      ),
      body: Column(
        children: [
          // テキスト入力エリア
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // リプライ先プレビュー
                  if (widget.replyToNote != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.replyToNote!.user.acct,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.replyToNote!.text != null)
                            Text(
                              widget.replyToNote!.text!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: widget.replyToNote != null
                            ? '${widget.replyToNote!.user.name} に返信...'
                            : '何かつぶやく...',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // 添付画像プレビュー
                  if (_attachedMedia.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachedMedia.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final media = _attachedMedia[i];
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: switch (media) {
                                    _LocalMedia m => Image.file(
                                      File(m.file.path),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                    _DriveMedia m =>
                                      m.driveFile.isImage
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  m.driveFile.thumbnailUrl ??
                                                  m.driveFile.url,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              width: 100,
                                              height: 100,
                                              color: theme
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .insert_drive_file_outlined,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                        ),
                                                    child: Text(
                                                      m.driveFile.name,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                  },
                                ),
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: GestureDetector(
                                    onTap: () => _removeMedia(i),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.colorScheme.onError,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // アップロード中インジケーター
          if (_isUploadingMedia)
            LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),

          // フッター上段
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                // アカウントアイコン（タップで切り替え）
                GestureDetector(
                  onTap: () => _showAccountSwitcher(context, ref),
                  child: account?.avatarUrl != null
                      ? CircleAvatar(
                          radius: 16,
                          backgroundImage: CachedNetworkImageProvider(
                            account!.avatarUrl!,
                          ),
                        )
                      : const CircleAvatar(
                          radius: 16,
                          child: Icon(Icons.person, size: 16),
                        ),
                ),
                const SizedBox(width: 8),

                // 文字数カウンター
                Text(
                  '$_charCount / $_charLimit',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isOverLimit
                        ? theme.colorScheme.error
                        : theme.colorScheme.outline,
                    fontWeight: _isOverLimit ? FontWeight.bold : null,
                  ),
                ),
                const Spacer(),

                // 公開範囲ボタン
                IconButton(
                  icon: Icon(_visibilityIcon(_visibility), size: 20),
                  tooltip: AppConstants.visibilityLabels[_visibility],
                  onPressed: _showVisibilityPicker,
                ),

                // 投稿ボタン
                FilledButton(
                  onPressed:
                      ((_textController.text.trim().isEmpty &&
                              _attachedMedia.isEmpty) ||
                          _isOverLimit ||
                          _isPosting)
                      ? null
                      : _post,
                  child: _isPosting
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('投稿'),
                ),
              ],
            ),
          ),

          // フッター下段
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                // メディア添付（最大4件）
                IconButton(
                  icon: _attachedMedia.isNotEmpty
                      ? Badge(
                          label: Text('${_attachedMedia.length}'),
                          child: const Icon(Icons.image_outlined),
                        )
                      : const Icon(Icons.image_outlined),
                  tooltip: 'メディアを添付（最大4件）',
                  onPressed: _isPosting ? null : _pickMedia,
                ),

                // 下書き一覧
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: '下書き一覧',
                  onPressed: () => context.push('/drafts'),
                ),

                // 絵文字ピッカー
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  tooltip: '絵文字',
                  onPressed: () async {
                    final name = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const EmojiPickerSheet(),
                    );
                    if (name != null && mounted) {
                      final pos = _textController.selection.baseOffset;
                      final text = _textController.text;
                      final insert = ':$name:';
                      final newText = pos < 0
                          ? text + insert
                          : text.substring(0, pos) +
                                insert +
                                text.substring(pos);
                      _textController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset: (pos < 0 ? text.length : pos) + insert.length,
                        ),
                      );
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),

          // キーボード分のスペース
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  IconData _visibilityIcon(String visibility) {
    return switch (visibility) {
      AppConstants.visibilityPublic => Icons.public,
      AppConstants.visibilityHome => Icons.home_outlined,
      AppConstants.visibilityFollowers => Icons.lock_outline,
      AppConstants.visibilitySpecified => Icons.mail_outline,
      _ => Icons.public,
    };
  }
}
