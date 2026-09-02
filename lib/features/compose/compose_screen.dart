import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
// wechat_assets_picker が内部で package:provider を使うため、その
// DefaultAssetPickerProvider を読むためだけに import している。
// 本アプリの状態管理は Riverpod で統一しており、新規用途では使用しないこと。
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/image_compression_level.dart';
import '../../core/errors/api_error_message.dart';
import '../../core/services/image_compression_service.dart';
import '../../data/local/hive_service.dart';
import '../../data/models/account_model.dart';
import '../../data/models/channel_model.dart';
import '../../data/models/custom_emoji_model.dart';
import '../../data/models/draft_local_file_model.dart';
import '../../data/models/draft_model.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';
import '../../data/remote/misskey_api.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/mention_history_provider.dart';
import '../../shared/providers/account_visibility_provider.dart';
import '../../shared/utils/media_type_utils.dart';
import '../../shared/utils/visibility_utils.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/custom_emoji_provider.dart';
import '../draft/draft_provider.dart';
import 'emoji_picker_sheet.dart';
import '../../shared/utils/emoji_utils.dart';
import '../../shared/widgets/mfm_content.dart';
import '../../shared/widgets/user_avatar.dart';

sealed class _AttachedMedia {}

final class _LocalMedia extends _AttachedMedia {
  final XFile file;
  ImageCompressionLevel compressionLevel;
  bool isSensitive;

  /// 圧縮中の Future。null の場合は圧縮しない（無圧縮）か非対象ファイル。
  Future<File>? compressFuture;

  _LocalMedia(this.file)
    : compressionLevel = ImageCompressionLevel.none,
      isSensitive = false,
      compressFuture = null;
}

final class _DriveMedia extends _AttachedMedia {
  final DriveFileModel driveFile;
  bool isSensitive;
  _DriveMedia(this.driveFile) : isSensitive = driveFile.isSensitive;
}

enum _MediaSource { gallery, osPicker, camera, drive, videoCamera, audio }

class ComposeScreen extends ConsumerStatefulWidget {
  final String? draftId;
  final String? replyId;
  final NoteModel? replyToNote;
  final String? renoteId;
  final NoteModel? renoteToNote;
  final String? initialText;
  final String? initialVisibility;
  final List<DriveFileModel>? initialFiles;
  final List<XFile>? initialLocalFiles;
  final String? initialCw;
  final String? initialChannelId;
  final bool initialIsSensitive;

  const ComposeScreen({
    super.key,
    this.draftId,
    this.replyId,
    this.replyToNote,
    this.renoteId,
    this.renoteToNote,
    this.initialText,
    this.initialVisibility,
    this.initialFiles,
    this.initialLocalFiles,
    this.initialCw,
    this.initialChannelId,
    this.initialIsSensitive = false,
  });

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _textController;
  late final TextEditingController _cwController;
  late String _visibility;
  String? _currentDraftId;
  final List<_AttachedMedia> _attachedMedia = [];
  bool _isPosting = false;
  bool _isUploadingMedia = false;
  bool _cwEnabled = false;
  bool _isReplyToDirect = false;
  bool _showPreview = false;
  List<CustomEmojiModel> _emojiSuggestions = [];
  List<UserModel> _userSuggestions = [];

  /// 入力のたびに users/search-by-username-and-host を叩かないためのデバウンス
  Timer? _userSuggestDebounce;

  /// 検索結果の到着順が入れ替わっても古い候補で上書きしないための世代番号
  int _userSuggestSeq = 0;

  /// 補完から選んだユーザー。投稿時の履歴記録で API 問い合わせを省くために持つ。
  /// キーは `username@host`（小文字）。
  final Map<String, UserModel> _pickedMentionUsers = {};
  AccountModel? _selectedAccount;
  String? _selectedChannelId;
  String? _selectedChannelName;
  Map<String, dynamic>? _poll;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _cwController = TextEditingController();
    _currentDraftId = widget.draftId;
    // 投稿アカウントを現在のアクティブアカウントで初期化（グローバル切り替えなし）
    _selectedAccount = ref.read(activeAccountProvider);
    // アカウント別のデフォルト公開範囲で初期化
    final accountId = _selectedAccount?.id ?? '';
    _visibility =
        widget.initialVisibility ??
        ref.read(accountVisibilityProvider(accountId));

    // 返信先がユーザー指定（specified）の場合は公開範囲を強制して永続化しない
    if (widget.replyToNote != null &&
        widget.replyToNote!.visibility == AppConstants.visibilitySpecified) {
      _visibility = AppConstants.visibilitySpecified;
      _isReplyToDirect = true;
    }

    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
    }

    if (widget.initialCw != null) {
      _cwController.text = widget.initialCw!;
      _cwEnabled = true;
    }

    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _attachedMedia.addAll(widget.initialFiles!.map((f) => _DriveMedia(f)));
    }

    // 引用の初期化: 特にファイル等は内包しないがプレビュー用に保持
    // (widget.renoteToNote が提供されれば UI でプレビュー表示される)

    if (widget.initialLocalFiles != null &&
        widget.initialLocalFiles!.isNotEmpty) {
      _attachedMedia.addAll(widget.initialLocalFiles!.map(_LocalMedia.new));
    }

    if (widget.draftId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 保存されているのはパスだけで実体が消えていることがあるため、
        // 読み込む前に取り除く。
        final removed = await ref
            .read(draftProvider.notifier)
            .pruneMissingLocalFiles(widget.draftId!);
        if (!mounted) return;
        final draft = ref
            .read(draftProvider.notifier)
            .getDraft(widget.draftId!);
        if (draft != null) {
          _textController.text = draft.text;
          setState(() {
            _visibility = draft.visibility;
            if (draft.cw != null && draft.cw!.isNotEmpty) {
              _cwController.text = draft.cw!;
              _cwEnabled = true;
            }
            _attachedMedia.addAll(_restoreAttachedMedia(draft));
          });
        }
        if (removed > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('端末から見つからない添付$removed件を除外しました')),
          );
        }
      });
    }

    // 初期チャネルが渡されていれば名前を取得して表示
    _selectedChannelId = widget.initialChannelId;
    if (_selectedChannelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final account = _selectedAccount;
        if (account == null) return;
        final api = MisskeyApi(host: account.host, token: account.token);
        try {
          final ch = await api.getChannel(_selectedChannelId!);
          if (mounted) {
            setState(() => _selectedChannelName = ch.name);
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _userSuggestDebounce?.cancel();
    _textController.dispose();
    _cwController.dispose();
    super.dispose();
  }

  int get _charCount => _textController.text.length;
  int get _charLimit => AppConstants.defaultNoteLimit;
  bool get _isOverLimit => _charCount > _charLimit;

  Future<void> _handleCancel() async {
    final settings = ref.read(settingsProvider);
    if ((_textController.text.trim().isEmpty && _attachedMedia.isEmpty) ||
        !settings.confirmDestructive) {
      context.pop();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('内容が変更されています。下書き保存しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保存しない'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存する'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (!result) {
      if (mounted) context.pop();
      return;
    }
    await _saveDraft();
  }

  /// 未アップロードの添付を下書き保存用の形式に変換する。
  ///
  /// 圧縮は「圧縮後のファイル」ではなく設定値だけを持ち回す。こうしておくと
  /// 下書きを開き直した後でもレベルを変更できる。
  List<DraftLocalFileModel> _collectLocalFiles() {
    final result = <DraftLocalFileModel>[];
    for (var i = 0; i < _attachedMedia.length; i++) {
      final media = _attachedMedia[i];
      if (media is! _LocalMedia) continue;
      result.add(
        DraftLocalFileModel(
          path: media.file.path,
          compressionLevel: media.compressionLevel,
          isSensitive: media.isSensitive,
          position: i,
        ),
      );
    }
    return result;
  }

  /// 下書きの添付を、保存時の並び順のまま復元する。
  List<_AttachedMedia> _restoreAttachedMedia(DraftModel draft) {
    final restored = draft.files.map<_AttachedMedia>(_DriveMedia.new).toList();
    final locals = draft.localFiles.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final local in locals) {
      final media = _LocalMedia(XFile(local.path))
        ..isSensitive = local.isSensitive;
      _restoreCompression(media, local.compressionLevel);
      // 位置が不明（旧形式）または範囲外なら末尾に置く。
      if (local.position < 0 || local.position > restored.length) {
        restored.add(media);
      } else {
        restored.insert(local.position, media);
      }
    }
    return restored;
  }

  /// 下書きから復元した添付に、保存されていた圧縮レベルを適用する。
  /// 設定の既定値で上書きしないよう [_applyDefaultCompression] とは分けている。
  void _restoreCompression(_LocalMedia media, ImageCompressionLevel level) {
    final isCompressible = ImageCompressionService.isCompressible(
      media.file.path,
    );
    media.compressionLevel = isCompressible
        ? level
        : ImageCompressionLevel.none;
    media.compressFuture =
        media.compressionLevel == ImageCompressionLevel.none
        ? null
        : ImageCompressionService.compress(
            file: File(media.file.path),
            level: media.compressionLevel,
          );
  }

  Future<void> _saveDraft() async {
    if (_textController.text.trim().isEmpty && _attachedMedia.isEmpty) {
      context.pop();
      return;
    }
    // isSensitiveはファイル単位で管理するため、変更された値をDriveFileModelに反映して保存
    final driveFiles = _attachedMedia
        .whereType<_DriveMedia>()
        .map(
          (m) => DriveFileModel(
            id: m.driveFile.id,
            name: m.driveFile.name,
            type: m.driveFile.type,
            url: m.driveFile.url,
            thumbnailUrl: m.driveFile.thumbnailUrl,
            size: m.driveFile.size,
            isSensitive: m.isSensitive,
          ),
        )
        .toList();
    _currentDraftId = await ref
        .read(draftProvider.notifier)
        .saveDraft(
          text: _textController.text,
          visibility: _visibility,
          existingId: _currentDraftId,
          files: driveFiles,
          localFiles: _collectLocalFiles(),
          cw: _cwEnabled && _cwController.text.isNotEmpty
              ? _cwController.text
              : null,
          isSensitive: false,
        );
    if (!mounted) return;

    // 保存先がメモリ上のみに落ちている場合、box.put() は成功し一覧にも出るが
    // 再起動で全部消える。保存できたと誤解させないよう明示する。
    if (HiveService.isVolatile(AppConstants.draftsBox)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存領域を利用できないため、この下書きはアプリを終了すると失われます。'),
          duration: Duration(seconds: 5),
        ),
      );
    }
    context.pop();
  }

  Future<void> _pickMedia() async {
    if (_attachedMedia.length >= 16) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添付できるファイルは最大16件です')));
      return;
    }
    final source = await showModalBottomSheet<_MediaSource>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('ギャラリーから画像/動画を選択'),
              onTap: () => Navigator.pop(context, _MediaSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('音声ファイルを選択'),
              onTap: () => Navigator.pop(context, _MediaSource.audio),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで写真を撮影'),
              onTap: () => Navigator.pop(context, _MediaSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('カメラで動画を撮影'),
              onTap: () => Navigator.pop(context, _MediaSource.videoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Misskeyドライブから選択'),
              onTap: () => Navigator.pop(context, _MediaSource.drive),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final remaining = 16 - _attachedMedia.length;

    if (source == _MediaSource.drive) {
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
      if (!mounted) return;
      final permOpt = PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      );
      final pickerAccentColor = Theme.of(context).colorScheme.primary;
      final ps = await AssetPicker.permissionCheck(requestOption: permOpt);
      if (!mounted) return;
      final pickerProvider = DefaultAssetPickerProvider(
        maxAssets: remaining,
        requestType: RequestType.common,
        // 1ページあたりの取得件数を増やし、無限スクロール時の
        // 逐次ロード回数を減らしてもたつきを軽減する（既定80）。
        pageSize: 240,
      );
      // OS標準ピッカーボタン経由の結果をここでキャプチャする。
      // AssetPicker は List<AssetEntity>? を返すため XFile を直接 pop できず、
      // デリゲートから onOsPickerSelected で受け取って null pop する方式を取る。
      List<XFile>? osPickerResult;
      final assets =
          await AssetPicker.pickAssetsWithDelegate<
            AssetEntity,
            AssetPathEntity,
            DefaultAssetPickerProvider
          >(
            context,
            delegate: _WideSelectPickerDelegate(
              provider: pickerProvider,
              initialPermission: ps,
              textDelegate: const _JaConfirmAssetPickerTextDelegate(),
              confirmDestructive: ref.read(settingsProvider).confirmDestructive,
              themeColor: pickerAccentColor,
              onOpenOsPicker: () async {
                final files = await picker.pickMultipleMedia(
                  limit: remaining >= 2 ? remaining : null,
                );
                return files.isEmpty ? null : files.take(remaining).toList();
              },
              onOsPickerSelected: (files) => osPickerResult = files,
            ),
            permissionRequestOption: permOpt,
          );
      // OS標準ピッカー経由の選択を優先処理する。
      if (osPickerResult != null && osPickerResult!.isNotEmpty) {
        final selected = osPickerResult!
            .map((xfile) => _LocalMedia(xfile))
            .toList();
        setState(() {
          for (final m in selected) {
            _applyDefaultCompression(m);
          }
          _attachedMedia.addAll(selected);
        });
        return;
      }
      if (assets != null && assets.isNotEmpty) {
        final files = await Future.wait(
          assets.map((a) async {
            final file = await a.originFile;
            if (file == null) return null;
            final xfile = XFile(file.path);
            return _LocalMedia(xfile);
          }),
        );
        final validFiles = files.whereType<_LocalMedia>().toList();
        if (validFiles.isNotEmpty) {
          setState(() {
            for (final m in validFiles) {
              _applyDefaultCompression(m);
            }
            _attachedMedia.addAll(validFiles);
          });
        }
      }
      return;
    }

    if (source == _MediaSource.osPicker) {
      // OS標準（Android Photo Picker等）で画像/動画を複数選択する。
      // limit は 2 未満だと例外になるため、残り枠が1のときは指定しない。
      final pickedFiles = await picker.pickMultipleMedia(
        limit: remaining >= 2 ? remaining : null,
      );
      if (pickedFiles.isNotEmpty) {
        // limit が無視されるプラットフォームに備えて残り枠でクランプする。
        final selected = pickedFiles
            .take(remaining)
            .map((xfile) => _LocalMedia(xfile))
            .toList();
        if (selected.isNotEmpty) {
          setState(() {
            for (final m in selected) {
              _applyDefaultCompression(m);
            }
            _attachedMedia.addAll(selected);
          });
        }
      }
      return;
    }

    if (source == _MediaSource.audio) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final selected = result.files
            .where((pf) => pf.path != null)
            .take(remaining)
            .map((pf) => _LocalMedia(XFile(pf.path!)))
            .toList();
        if (selected.isNotEmpty) {
          setState(() {
            for (final m in selected) {
              _applyDefaultCompression(m);
            }
            _attachedMedia.addAll(selected);
          });
        }
      }
      return;
    }

    if (source == _MediaSource.videoCamera) {
      final file = await picker.pickVideo(source: ImageSource.camera);
      if (file != null) {
        final media = _LocalMedia(file);
        _applyDefaultCompression(media);
        setState(() => _attachedMedia.add(media));
      }
      return;
    }

    if (source == _MediaSource.camera) {
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file != null) {
        final media = _LocalMedia(file);
        _applyDefaultCompression(media);
        setState(() => _attachedMedia.add(media));
      }
    }
  }

  void _removeMedia(int index) {
    setState(() => _attachedMedia.removeAt(index));
  }

  /// ローカル画像メディアにデフォルト圧縮レベルを適用して圧縮を開始する
  void _applyDefaultCompression(_LocalMedia media) {
    final defaultLevel = ref
        .read(settingsProvider)
        .defaultImageCompressionLevel;
    if (!ImageCompressionService.isCompressible(media.file.path)) {
      media.compressionLevel = ImageCompressionLevel.none;
      media.compressFuture = null;
      return;
    }
    media.compressionLevel = defaultLevel;
    if (defaultLevel == ImageCompressionLevel.none) {
      media.compressFuture = null;
    } else {
      media.compressFuture = ImageCompressionService.compress(
        file: File(media.file.path),
        level: defaultLevel,
      );
    }
  }

  /// 圧縮レベルを変更して圧縮を再開する
  void _changeCompression(_LocalMedia media, ImageCompressionLevel level) {
    setState(() {
      media.compressionLevel = level;
      if (level == ImageCompressionLevel.none ||
          !ImageCompressionService.isCompressible(media.file.path)) {
        media.compressFuture = null;
      } else {
        media.compressFuture = ImageCompressionService.compress(
          file: File(media.file.path),
          level: level,
        );
      }
    });
  }

  /// メディア設定シートを表示する（圧縮率 + センシティブ設定）
  Future<void> _showMediaSettings(_AttachedMedia media) async {
    final _LocalMedia? localMedia = media is _LocalMedia ? media : null;
    final isCompressible =
        localMedia != null &&
        ImageCompressionService.isCompressible(localMedia.file.path);

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheetState) {
          final currentSensitive = switch (media) {
            _LocalMedia m => m.isSensitive,
            _DriveMedia m => m.isSensitive,
          };
          final currentLevel = localMedia?.compressionLevel;

          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'メディアの設定',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (isCompressible) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '画像の圧縮',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  ...ImageCompressionLevel.values.map(
                    (level) => ListTile(
                      leading: Icon(_compressionIcon(level)),
                      title: Text(level.label),
                      subtitle: level == ImageCompressionLevel.none
                          ? const Text('そのままアップロード')
                          : Text(
                              '最大 ${level.maxDimension}px / JPEG品質 ${level.quality}%',
                            ),
                      trailing: currentLevel == level
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () {
                        _changeCompression(localMedia, level);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  secondary: Icon(
                    currentSensitive
                        ? Icons.disabled_visible
                        : Icons.disabled_visible_outlined,
                  ),
                  title: const Text('センシティブ設定'),
                  subtitle: const Text('このメディアをセンシティブとしてマーク'),
                  value: currentSensitive,
                  onChanged: (v) {
                    if (media is _LocalMedia) media.isSensitive = v;
                    if (media is _DriveMedia) media.isSensitive = v;
                    setState(() {});
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _compressionIcon(ImageCompressionLevel level) {
    return switch (level) {
      ImageCompressionLevel.none => Icons.image_outlined,
      ImageCompressionLevel.low => Icons.compress,
      ImageCompressionLevel.medium => Icons.compress,
      ImageCompressionLevel.high => Icons.compress,
    };
  }

  /// テキスト変更時に絵文字／メンションのサジェストを更新する。
  ///
  /// `:` と `@` の両方が入力済みのこともあるため、カーソルに近い方だけを
  /// 有効なトリガーとして扱い、もう一方の候補は消す。
  void _updateSuggestions(String text) {
    final selection = _textController.selection;
    if (!selection.isValid || selection.baseOffset < 0) {
      _clearSuggestions();
      return;
    }
    final cursorPos = selection.baseOffset.clamp(0, text.length);
    final textBeforeCursor = text.substring(0, cursorPos);
    if (textBeforeCursor.lastIndexOf('@') >
        textBeforeCursor.lastIndexOf(':')) {
      _updateMentionSuggestions(textBeforeCursor);
    } else {
      _updateEmojiSuggestions(textBeforeCursor);
    }
  }

  void _clearSuggestions() {
    _userSuggestDebounce?.cancel();
    // 発行済みのリクエストが後から候補を復活させないよう、世代を進めて無効化する
    _userSuggestSeq++;
    if (_emojiSuggestions.isEmpty && _userSuggestions.isEmpty) return;
    setState(() {
      _emojiSuggestions = [];
      _userSuggestions = [];
    });
  }

  void _updateEmojiSuggestions(String textBeforeCursor) {
    final lastColon = textBeforeCursor.lastIndexOf(':');
    if (lastColon < 0) {
      _clearSuggestions();
      return;
    }
    final partial = textBeforeCursor.substring(lastColon + 1);
    // スペース・改行・コロンが含まれる場合はサジェスト非表示
    if (partial.isEmpty ||
        partial.contains(' ') ||
        partial.contains('\n') ||
        partial.contains(':')) {
      _clearSuggestions();
      return;
    }
    final emojis = ref.read(customEmojisProvider).value ?? [];
    final q = partial.toLowerCase();
    final suggestions = emojis
        .where((e) => e.name.toLowerCase().contains(q))
        .take(20)
        .toList();
    _userSuggestDebounce?.cancel();
    _userSuggestSeq++;
    setState(() {
      _emojiSuggestions = suggestions;
      _userSuggestions = [];
    });
  }

  /// メンション補完のトリガー。行頭または空白の直後の `@` だけを拾い、
  /// メールアドレスや `@user@host` の2つ目の `@` を誤検出しないようにする。
  /// group(1)=ユーザー名部分, group(2)=ホスト部分（`@` が1つなら null）。
  static final RegExp _mentionTriggerRegExp = RegExp(
    r'(?:^|\s)@([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9._-]*))?$',
  );

  /// 本文から送信済みメンションを拾うための正規表現（投稿後の履歴記録用）
  static final RegExp _mentionRegExp = RegExp(
    r'(?:^|\s)@([a-zA-Z0-9_]+)(?:@([a-zA-Z0-9._-]+))?',
  );

  void _updateMentionSuggestions(String textBeforeCursor) {
    final match = _mentionTriggerRegExp.firstMatch(textBeforeCursor);
    if (match == null) {
      _clearSuggestions();
      return;
    }
    final username = match.group(1) ?? '';
    final userHost = match.group(2);

    // 履歴は手元にあるので、API 応答を待たずに先に出す
    final history = _matchedHistory(username, userHost);
    setState(() {
      _emojiSuggestions = [];
      _userSuggestions = history;
    });

    final seq = ++_userSuggestSeq;
    _userSuggestDebounce?.cancel();
    // `@` だけの時点で全ユーザーを引くと候補が無意味に広がるため、履歴だけを見せる
    if (username.isEmpty && userHost == null) return;
    _userSuggestDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _fetchUserSuggestions(username, userHost, seq),
    );
  }

  /// 入力中の文字列に前方一致する履歴を新しい順で返す
  List<UserModel> _matchedHistory(String username, String? userHost) {
    final account = _selectedAccount;
    if (account == null) return const [];
    final q = username.toLowerCase();
    final hostQ = userHost?.toLowerCase();
    return ref
        .read(mentionHistoryProvider(account.id))
        .where((e) {
          if (!e.username.toLowerCase().startsWith(q)) return false;
          if (hostQ == null) return true;
          return e.host.toLowerCase().startsWith(hostQ);
        })
        .map((e) => e.toUserModel())
        .toList();
  }

  Future<void> _fetchUserSuggestions(
    String username,
    String? userHost,
    int seq,
  ) async {
    final account = _selectedAccount;
    if (account == null) return;
    final api = MisskeyApi(host: account.host, token: account.token);
    try {
      final users = await api.searchUsersByUsernameAndHost(
        username: username,
        userHost: userHost,
      );
      if (!mounted || seq != _userSuggestSeq) return;
      // 履歴由来の候補を上位に残したまま、重複しないものだけを後ろに足す
      final shownIds = _userSuggestions.map((u) => u.id).toSet();
      setState(() {
        _userSuggestions = [
          ..._userSuggestions,
          ...users.where((u) => !shownIds.contains(u.id)),
        ];
      });
    } catch (_) {
      // 補完は付加機能なので、失敗時は履歴だけ出したままにする
    }
  }

  /// サジェストから絵文字を選択して挿入する
  void _insertEmojiSuggestion(String name) {
    final selection = _textController.selection;
    final text = _textController.text;
    final cursorPos = (selection.isValid && selection.baseOffset >= 0)
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastColon = textBeforeCursor.lastIndexOf(':');
    if (lastColon < 0) return;
    final insert = ':$name:';
    final newText =
        text.substring(0, lastColon) + insert + text.substring(cursorPos);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lastColon + insert.length),
    );
    setState(() => _emojiSuggestions = []);
  }

  /// サジェストからユーザーを選択してメンションを挿入する
  void _insertMentionSuggestion(UserModel user) {
    final selection = _textController.selection;
    final text = _textController.text;
    final cursorPos = (selection.isValid && selection.baseOffset >= 0)
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final textBeforeCursor = text.substring(0, cursorPos);
    final match = _mentionTriggerRegExp.firstMatch(textBeforeCursor);
    if (match == null) return;
    final atIndex = textBeforeCursor.indexOf('@', match.start);

    final insert = '${_acctFor(user)} ';
    final newText =
        text.substring(0, atIndex) + insert + text.substring(cursorPos);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIndex + insert.length),
    );
    _pickedMentionUsers[_mentionKey(user.username, user.host)] = user;
    _userSuggestDebounce?.cancel();
    setState(() => _userSuggestions = []);
  }

  /// 本文に書き込むメンション表記。自ホストのユーザーはホスト部を省く。
  String _acctFor(UserModel user) {
    final account = _selectedAccount;
    if (user.host.isEmpty || user.host == account?.host) {
      return '@${user.username}';
    }
    return '@${user.username}@${user.host}';
  }

  /// メンションの同一性を判定するキー。ホスト省略表記と完全表記を同じものとして扱う。
  String _mentionKey(String username, String? userHost) {
    final host = (userHost == null || userHost.isEmpty)
        ? (_selectedAccount?.host ?? '')
        : userHost;
    return '${username.toLowerCase()}@${host.toLowerCase()}';
  }

  /// 投稿した相手をメンション履歴に積む。
  ///
  /// 画面を閉じた後に走るため [ref]・[setState] には触れず、必要なものは引数で受け取る。
  /// 手入力されたメンションは補完キャッシュに無いので `users/show` で解決するが、
  /// 打ち間違いなどで解決できないものは黙って捨てる。
  Future<void> _recordMentionHistory(
    MentionHistoryNotifier notifier,
    MisskeyApi api,
    AccountModel account,
    String text,
  ) async {
    final resolved = <String, UserModel>{};
    final unresolved = <String, ({String username, String? host})>{};

    void addUser(UserModel user) {
      if (user.id == account.userId) return;
      resolved[_mentionKey(user.username, user.host)] = user;
    }

    // 返信相手を先に積み、履歴の最上位に来るようにする
    if (widget.replyId != null && widget.replyToNote != null) {
      addUser(widget.replyToNote!.user);
    }

    for (final match in _mentionRegExp.allMatches(text)) {
      final username = match.group(1)!;
      final userHost = match.group(2);
      final key = _mentionKey(username, userHost);
      if (resolved.containsKey(key) || unresolved.containsKey(key)) continue;
      final picked = _pickedMentionUsers[key];
      if (picked != null) {
        addUser(picked);
        continue;
      }
      if (username.toLowerCase() == account.username.toLowerCase() &&
          (userHost == null ||
              userHost.toLowerCase() == account.host.toLowerCase())) {
        continue;
      }
      unresolved[key] = (username: username, host: userHost);
    }

    for (final target in unresolved.values) {
      try {
        addUser(
          await api.getUserByUsername(
            target.username,
            userHost: target.host == account.host ? null : target.host,
          ),
        );
      } catch (_) {}
    }

    await notifier.record(resolved.values);
  }

  Future<void> _post() async {
    if (_textController.text.trim().isEmpty && _attachedMedia.isEmpty) return;
    if (_isOverLimit || _isPosting) return;

    // 投稿に使用するAPIは _selectedAccount から生成（グローバル切り替えなし）
    final account = _selectedAccount;
    if (account == null) return;
    final api = MisskeyApi(host: account.host, token: account.token);

    setState(() => _isPosting = true);

    try {
      // メディアを先にアップロード（端末のファイルのみアップロード、ドライブはIDをそのまま使用）
      final fileIds = <String>[];
      if (_attachedMedia.isNotEmpty) {
        setState(() => _isUploadingMedia = true);
        try {
          for (final media in _attachedMedia) {
            if (media is _LocalMedia) {
              // 圧縮が進行中の場合は完了を待つ
              File uploadFile;
              if (media.compressFuture != null) {
                uploadFile = await media.compressFuture!;
              } else {
                uploadFile = File(media.file.path);
              }
              final id = await api.uploadFile(
                uploadFile,
                isSensitive: media.isSensitive,
              );
              fileIds.add(id);
            } else if (media is _DriveMedia) {
              // センシティブ設定が変更された場合はドライブファイルを更新
              if (media.isSensitive != media.driveFile.isSensitive) {
                await api.updateFileSensitive(
                  media.driveFile.id,
                  isSensitive: media.isSensitive,
                );
              }
              fileIds.add(media.driveFile.id);
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isPosting = false;
              _isUploadingMedia = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(apiErrorMessage(e, fallback: 'アップロードに失敗しました')),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
          return;
        }
        setState(() => _isUploadingMedia = false);
      }

      List<String>? visibleUserIds;
      if (_visibility == AppConstants.visibilitySpecified &&
          widget.replyToNote != null) {
        visibleUserIds = [widget.replyToNote!.user.id];
      }

      await api.createNote(
        text: _textController.text.trim().isEmpty ? null : _textController.text,
        cw: _cwEnabled && _cwController.text.isNotEmpty
            ? _cwController.text
            : null,
        visibility: _visibility,
        fileIds: fileIds,
        replyId: widget.replyId,
        renoteId: widget.renoteId,
        visibleUserIds: visibleUserIds,
        poll: _poll,
        channelId: _selectedChannelId,
      );

      // 画面を閉じた後も走らせたいので、ref に触るのは pop の前に済ませる。
      // 履歴記録の失敗や遅延で投稿完了を待たせないため、あえて await しない。
      unawaited(
        _recordMentionHistory(
          ref.read(mentionHistoryProvider(account.id).notifier),
          api,
          account,
          _textController.text,
        ),
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
            content: Text(apiErrorMessage(e, fallback: '投稿に失敗しました')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _showPollEditor() async {
    // Prepare controllers and state outside the modal builder so they persist across rebuilds
    final existing = _poll;
    final initChoices = (existing != null && existing['choices'] is List)
        ? List<String>.from(existing['choices'] as List)
        : <String>['', ''];
    final controllers = initChoices
        .map((s) => TextEditingController(text: s))
        .toList();
    bool multiple = existing != null
        ? (existing['multiple'] as bool? ?? false)
        : false;
    int expiresHours = 0;
    if (existing != null && existing['expiresAt'] is String) {
      try {
        final dt = DateTime.parse(existing['expiresAt'] as String);
        expiresHours = dt.difference(DateTime.now()).inHours.clamp(0, 9999);
      } catch (_) {}
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              // keyboard inset + system nav bar safe area will be respected by SafeArea
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              left: 16,
              right: 16,
              top: 12,
            ),
            child: StatefulBuilder(
              builder: (c, setModalState) {
                void addChoice() {
                  if (controllers.length >= 6) return;
                  controllers.add(TextEditingController());
                  setModalState(() {});
                }

                void removeChoice(int idx) {
                  if (controllers.length <= 2) return;
                  controllers.removeAt(idx);
                  setModalState(() {});
                }

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Text(
                              '投票を作成',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('キャンセル'),
                            ),
                          ],
                        ),
                      ),
                      ...List.generate(controllers.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controllers[i],
                                  decoration: InputDecoration(
                                    hintText: '選択肢 ${i + 1}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (controllers.length > 2)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => removeChoice(i),
                                ),
                            ],
                          ),
                        );
                      }),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: addChoice,
                            icon: const Icon(Icons.add),
                            label: const Text('選択肢を追加'),
                          ),
                          const Spacer(),
                        ],
                      ),
                      SwitchListTile(
                        value: multiple,
                        onChanged: (v) => setModalState(() => multiple = v),
                        title: const Text('複数選択を許可'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Text('有効期限（時間）:'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '0 (無期限)',
                                ),
                                onChanged: (v) => setModalState(
                                  () => expiresHours = int.tryParse(v) ?? 0,
                                ),
                                controller: TextEditingController(
                                  text: expiresHours > 0 ? '$expiresHours' : '',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final choices = controllers
                                    .map((c) => c.text.trim())
                                    .where((s) => s.isNotEmpty)
                                    .toList();
                                if (choices.length < 2) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('選択肢は2つ以上必要です'),
                                    ),
                                  );
                                  return;
                                }
                                final Map<String, dynamic> out = {
                                  'choices': choices,
                                  'multiple': multiple,
                                };
                                if (expiresHours > 0) {
                                  out['expiresAt'] = DateTime.now()
                                      .add(Duration(hours: expiresHours))
                                      .toIso8601String();
                                  out['expiresHours'] = expiresHours;
                                }
                                Navigator.pop(ctx, out);
                              },
                              child: const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() => _poll = result);
    }
  }

  void _showVisibilityPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '公開範囲',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...(_isReplyToDirect
                    ? AppConstants.visibilityLabels.entries.where(
                        (entry) =>
                            entry.key == AppConstants.visibilitySpecified,
                      )
                    : AppConstants.visibilityLabels.entries)
                .map(
                  (e) => ListTile(
                    leading: Icon(visibilityIcon(e.key)),
                    title: Text(e.value),
                    trailing: _visibility == e.key
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      setState(() => _visibility = e.key);
                      // 返信先がユーザー指定の場合は変更を永続化しない
                      if (!_isReplyToDirect) {
                        final accountId =
                            ref.read(activeAccountProvider)?.id ?? '';
                        ref
                            .read(accountVisibilityProvider(accountId).notifier)
                            .setVisibility(e.key);
                      }
                      Navigator.pop(context);
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context, WidgetRef ref) {
    final accounts = ref.read(accountProvider);
    if (accounts.length <= 1) return; // 1アカウントのみなら何もしない
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
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
                leading: UserAvatar(avatarUrl: a.avatarUrl),
                title: Text(a.name),
                subtitle: Text(a.acct),
                trailing: a.id == (_selectedAccount?.id)
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  // グローバルアカウントは切り替えず、この投稿のみに適用
                  final newVisibility = ref.read(
                    accountVisibilityProvider(a.id),
                  );
                  setState(() {
                    _selectedAccount = a;
                    // 返信先がユーザー指定の場合は公開範囲を強制（永続化しない）
                    _visibility = _isReplyToDirect
                        ? AppConstants.visibilitySpecified
                        : newVisibility;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<ChannelModel>> _fetchChannels(MisskeyApi api) async {
    final followed = await api.getChannelsFollowed(limit: 100);
    final owned = await api.getChannelsOwned(limit: 100);
    final map = <String, ChannelModel>{};
    for (final c in [...followed, ...owned]) {
      if (c.id.isNotEmpty) map[c.id] = c;
    }
    final list = map.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// チャンネル選択シートで「なし」を選んだことを表す番兵。
  static final _noChannel = ChannelModel(id: '', name: '');

  Future<void> _showChannelPicker() async {
    final account = _selectedAccount ?? ref.read(activeAccountProvider);
    if (account == null) return;
    final api = MisskeyApi(host: account.host, token: account.token);
    final selected = await showModalBottomSheet<ChannelModel>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'チャンネルを選択',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<ChannelModel>>(
                      future: _fetchChannels(api),
                      builder: (c, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text('チャンネルの読み込みに失敗しました: ${snap.error}'),
                            ),
                          );
                        }
                        final list = snap.data ?? [];
                        return ListView.separated(
                          itemCount: list.length + 1,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (ctx2, i) {
                            if (i == 0) {
                              return ListTile(
                                title: const Text('なし（チャンネル選択を解除）'),
                                onTap: () => Navigator.pop(ctx, _noChannel),
                              );
                            }
                            final ch = list[i - 1];
                            final name = ch.name;
                            final desc = ch.description;
                            return ListTile(
                              title: Text(name),
                              subtitle: desc != null && desc.isNotEmpty
                                  ? Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(ctx, ch),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    if (selected.id.isEmpty) {
      setState(() {
        _selectedChannelId = null;
        _selectedChannelName = null;
      });
    } else {
      setState(() {
        _selectedChannelId = selected.id;
        _selectedChannelName = selected.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _selectedAccount ?? ref.read(activeAccountProvider);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleCancel();
      },
      child: TooltipTheme(
        data: const TooltipThemeData(preferBelow: false),
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: TextButton(
              onPressed: _handleCancel,
              child: const Text('キャンセル', softWrap: false),
            ),
            leadingWidth: 110,
            actions: [
              TextButton.icon(
                onPressed: _saveDraft,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('下書き保存'),
              ),
            ],
          ),
          body: Column(
            children: [
              // リプライ先プレビュー（テキストエリアの外に固定表示）
              if (widget.replyToNote != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
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

              // 引用プレビュー（引用して投稿する場合）
              if (widget.renoteToNote != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_quote, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            widget.renoteToNote!.user.acct,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (widget.renoteToNote!.text != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            widget.renoteToNote!.text!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      if (widget.renoteToNote!.files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(
                            height: 80,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.renoteToNote!.files.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final f = widget.renoteToNote!.files[i];
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: f.isImage
                                      ? CachedNetworkImage(
                                          cacheManager: AppCacheManager(),
                                          imageUrl: f.thumbnailUrl ?? f.url,
                                          width: 140,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 140,
                                          height: 80,
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                f.isVideo
                                                    ? Icons.play_arrow
                                                    : Icons
                                                          .insert_drive_file_outlined,
                                                size: 28,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                f.name,
                                                style:
                                                    theme.textTheme.labelSmall,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // CW入力エリア
              if (_cwEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _cwController,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: '警告文言（CW）...',
                      prefixIcon: const Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                      ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),

              // テキスト入力 / MFMプレビュー切り替えエリア
              Expanded(
                child: _showPreview
                    ? _MfmPreviewArea(text: _textController.text)
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          autofocus: true,
                          scrollPadding: EdgeInsets.zero,
                          decoration: InputDecoration(
                            hintText: widget.replyToNote != null
                                ? '${widget.replyToNote!.user.name} に返信...'
                                : '何かつぶやく...',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) {
                            setState(() {});
                            _updateSuggestions(_textController.text);
                          },
                        ),
                      ),
              ),

              // 絵文字サジェストバー
              if (_emojiSuggestions.isNotEmpty)
                _EmojiSuggestBar(
                  suggestions: _emojiSuggestions,
                  onSelect: _insertEmojiSuggestion,
                ),

              // メンションサジェストバー
              if (_userSuggestions.isNotEmpty)
                _MentionSuggestBar(
                  suggestions: _userSuggestions,
                  acctOf: _acctFor,
                  onSelect: _insertMentionSuggestion,
                ),

              // 投票プレビュー
              if (_poll != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.poll, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (_poll?['choices'] as List<dynamic>)
                                .take(3)
                                .join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ((_poll?['multiple'] as bool? ?? false))
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '複数可',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: '投票を削除',
                          onPressed: () => setState(() => _poll = null),
                        ),
                      ],
                    ),
                  ),
                ),

              // 添付画像プレビュー（テキストエリアとフッターの間）
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
                            GestureDetector(
                              onTap: () => _showMediaSettings(media),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: switch (media) {
                                  _LocalMedia m =>
                                    isImagePath(m.file.path)
                                        ? Image.file(
                                            File(m.file.path),
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
                                                  isVideoPath(m.file.path)
                                                      ? Icons.play_arrow
                                                      : Icons.audiotrack,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                                const SizedBox(height: 6),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      ),
                                                  child: Text(
                                                    File(
                                                      m.file.path,
                                                    ).uri.pathSegments.last,
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  _DriveMedia m =>
                                    m.driveFile.isImage
                                        ? CachedNetworkImage(
                                            cacheManager: AppCacheManager(),
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
                                                  color:
                                                      theme.colorScheme.primary,
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
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                },
                              ),
                            ),
                            // 圧縮アイコン（ローカル画像かつ圧縮対象の場合）
                            if (media is _LocalMedia &&
                                ImageCompressionService.isCompressible(
                                  media.file.path,
                                ))
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        media.compressionLevel ==
                                            ImageCompressionLevel.none
                                        ? theme.colorScheme.surface.withValues(
                                            alpha: 0.75,
                                          )
                                        : theme.colorScheme.primary.withValues(
                                            alpha: 0.85,
                                          ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        media.compressionLevel ==
                                                ImageCompressionLevel.none
                                            ? Icons.image_outlined
                                            : Icons.compress,
                                        size: 12,
                                        color:
                                            media.compressionLevel ==
                                                ImageCompressionLevel.none
                                            ? theme.colorScheme.onSurface
                                            : theme.colorScheme.onPrimary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        media.compressionLevel.label,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              fontSize: 9,
                                              color:
                                                  media.compressionLevel ==
                                                      ImageCompressionLevel.none
                                                  ? theme.colorScheme.onSurface
                                                  : theme.colorScheme.onPrimary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // センシティブインジケーター
                            if (switch (media) {
                              _LocalMedia m => m.isSensitive,
                              _DriveMedia m => m.isSensitive,
                            })
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error.withValues(
                                      alpha: 0.85,
                                    ),
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
                                    size: 22,
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

              // アップロード中インジケーター
              if (_isUploadingMedia)
                LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),

              // フッター上段
              Container(
                // 下段で SafeArea を使っているためここではナビゲーションバー分の余白は付けない
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
                      child: UserAvatar(
                        avatarUrl: account?.avatarUrl,
                        radius: 16,
                        iconSize: 16,
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
                    const SizedBox(width: 8),

                    // チャンネル選択ボタン
                    IconButton(
                      icon: Icon(
                        Icons.tag,
                        size: 20,
                        color: _selectedChannelId != null
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      tooltip: _selectedChannelName != null
                          ? 'チャンネル: ${_selectedChannelName!}'
                          : 'チャンネルを選択',
                      onPressed: _showChannelPicker,
                    ),

                    // チャンネル名を Expanded で中央エリアに収める（右側ボタンを押し出さない）
                    Expanded(
                      child: _selectedChannelName != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: InputChip(
                                label: Text(
                                  _selectedChannelName!.isEmpty
                                      ? 'チャンネル'
                                      : _selectedChannelName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                onDeleted: () => setState(() {
                                  _selectedChannelId = null;
                                  _selectedChannelName = null;
                                }),
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                shape: StadiumBorder(
                                  side: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // 公開範囲ボタン
                    IconButton(
                      icon: Icon(visibilityIcon(_visibility), size: 20),
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
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      // メディア添付（最大16件）
                      IconButton(
                        icon: _attachedMedia.isNotEmpty
                            ? Badge(
                                label: Text('${_attachedMedia.length}'),
                                child: const Icon(Icons.image_outlined),
                              )
                            : const Icon(Icons.image_outlined),
                        tooltip: 'メディアを添付（最大16件）',
                        onPressed: _isPosting ? null : _pickMedia,
                      ),

                      // 下書き一覧
                      IconButton(
                        icon: const Icon(Icons.edit_note),
                        tooltip: '下書き一覧',
                        onPressed: () => context.push('/drafts'),
                      ),

                      // CWトグル
                      IconButton(
                        icon: Icon(
                          Icons.warning_amber_outlined,
                          color: _cwEnabled ? theme.colorScheme.primary : null,
                        ),
                        tooltip: 'CW（警告文言）',
                        onPressed: () => setState(() {
                          _cwEnabled = !_cwEnabled;
                          if (!_cwEnabled) _cwController.clear();
                        }),
                      ),

                      // 投票作成
                      IconButton(
                        icon: Icon(
                          Icons.poll,
                          color: _poll != null
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        tooltip: '投票を追加',
                        onPressed: _isPosting ? null : _showPollEditor,
                      ),

                      // MFMプレビュートグル
                      IconButton(
                        icon: Icon(
                          Icons.visibility_outlined,
                          color: _showPreview
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        tooltip: _showPreview ? '編集に戻る' : 'MFMプレビュー',
                        onPressed: () =>
                            setState(() => _showPreview = !_showPreview),
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
                            final insert = name;
                            final newText = pos < 0
                                ? text + insert
                                : text.substring(0, pos) +
                                      insert +
                                      text.substring(pos);
                            _textController.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset:
                                    (pos < 0 ? text.length : pos) +
                                    insert.length,
                              ),
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- MFMプレビューエリア ----

class _MfmPreviewArea extends ConsumerWidget {
  final String text;
  const _MfmPreviewArea({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (text.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'プレビューするテキストがありません',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: MfmContent(
        text: text,
        emojiResolver: EmojiResolver(
          instanceEmojis: ref.watch(customEmojiUrlMapProvider),
        ),
        enableAnimations: true,
      ),
    );
  }
}

// ---- 絵文字サジェストバー ----

class _EmojiSuggestBar extends ConsumerWidget {
  final List<CustomEmojiModel> suggestions;
  final void Function(String name) onSelect;

  const _EmojiSuggestBar({required this.suggestions, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 絵文字URLマップ
    final urlMap = ref.watch(customEmojiUrlMapProvider);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final emoji = suggestions[i];
          final name = emoji.name;
          final url = urlMap[name] ?? emoji.url;
          return InkWell(
            onTap: () => onSelect(name),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (url != null)
                    CachedNetworkImage(
                      cacheManager: AppCacheManager(),
                      imageUrl: url,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.emoji_emotions, size: 20),
                    )
                  else
                    const Icon(Icons.emoji_emotions, size: 20),
                  const SizedBox(width: 4),
                  Text(':$name:', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---- メンションサジェストバー ----

class _MentionSuggestBar extends StatelessWidget {
  final List<UserModel> suggestions;

  /// 本文に挿入されるのと同じ表記をチップに出すため、変換は呼び出し元に任せる
  final String Function(UserModel user) acctOf;
  final void Function(UserModel user) onSelect;

  const _MentionSuggestBar({
    required this.suggestions,
    required this.acctOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final user = suggestions[i];
          return InkWell(
            onTap: () => onSelect(user),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(avatarUrl: user.avatarUrl, radius: 12),
                  const SizedBox(width: 6),
                  Text(acctOf(user), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _JaConfirmAssetPickerTextDelegate
    extends JapaneseAssetPickerTextDelegate {
  const _JaConfirmAssetPickerTextDelegate();

  @override
  String get confirm => '確定';
}

/// ビューアーで「選択」テキスト部分もタップ可能にするカスタムデリゲート
class _WideSelectViewerDelegate
    extends DefaultAssetPickerViewerBuilderDelegate {
  _WideSelectViewerDelegate({
    required super.currentIndex,
    required super.previewAssets,
    required super.themeData,
    super.selectorProvider,
    super.provider,
    super.selectedAssets,
    super.previewThumbnailSize,
    super.maxAssets,
    super.shouldReversePreview,
    super.selectPredicate,
    super.shouldAutoplayPreview,
  });

  @override
  Widget selectButton(BuildContext context) {
    return StreamBuilder<int>(
      initialData: currentIndex,
      stream: pageStreamController.stream,
      builder: (ctx, snapshot) {
        final index = snapshot.requireData;
        final assetIndex = shouldReversePreview
            ? previewAssets.length - index - 1
            : index;
        if (assetIndex < 0 || assetIndex >= previewAssets.length) {
          return const SizedBox.shrink();
        }
        final asset = previewAssets.elementAt(assetIndex);
        final p = provider;
        if (p == null) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: p,
          builder: (context, _) {
            final bool isSelected = p.currentlySelectedAssets.contains(asset);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChangingSelected(context, asset, isSelected),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: isSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999999),
                    ),
                    onChanged: null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Text(
                    textDelegate.select,
                    style: const TextStyle(fontSize: 17, height: 1.2),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// ギャラリーピッカー用カスタムデリゲート（_WideSelectViewerDelegate を使用）
class _WideSelectPickerDelegate extends DefaultAssetPickerBuilderDelegate {
  // super に固定値（dragToSelect/gridCount）を渡すため明示的な super 呼び出しが必要
  // ignore: use_super_parameters
  _WideSelectPickerDelegate({
    required DefaultAssetPickerProvider provider,
    required PermissionState initialPermission,
    AssetPickerTextDelegate? textDelegate,
    Color? themeColor,
    required this.confirmDestructive,
    required this.onOpenOsPicker,
    required this.onOsPickerSelected,
  }) : super(
         provider: provider,
         initialPermission: initialPermission,
         textDelegate: textDelegate,
         themeColor: themeColor,
         // スクロール中の指の動きが pan ジェスチャとして拾われ、なぞった
         // タイルが連続選択されてしまう「ドラッグ選択」を無効化する。
         // （未指定だと !accessibleNavigation にフォールバックし通常端末では有効になる）
         dragToSelect: false,
       );

  final bool confirmDestructive;

  /// OS標準ピッカーを起動し、選択結果を [List<XFile>] で返す。
  /// null / 空の場合は操作なし（キャンセル等）とみなす。
  final Future<List<XFile>?> Function() onOpenOsPicker;

  /// OS標準ピッカーで選択が確定したとき、XFile リストを呼び出し元に渡す。
  /// デリゲートはこの後 null でピッカーを閉じる。
  final void Function(List<XFile>) onOsPickerSelected;

  @override
  AssetPickerAppBar appBar(BuildContext context) {
    final base = super.appBar(context);
    return AssetPickerAppBar(
      title: base.title,
      leading: base.leading,
      blurRadius: base.blurRadius,
      actions: [
        IconButton(
          tooltip: 'OS標準ピッカーで開く',
          icon: const Icon(Icons.collections_outlined),
          onPressed: () async {
            final xfiles = await onOpenOsPicker();
            if (xfiles == null || xfiles.isEmpty) return;
            onOsPickerSelected(xfiles);
            // List<XFile> を直接 pop すると型不一致エラーになるため、
            // 結果は onOsPickerSelected で渡し、ピッカー自体は null で閉じる。
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }

  Future<void> _clearAllSelections(BuildContext context) async {
    if (confirmDestructive) {
      final errorColor = theme.colorScheme.error;
      final onErrorColor = theme.colorScheme.onError;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('選択を全て解除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: errorColor,
                foregroundColor: onErrorColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.deselect_outlined, size: 18),
              label: const Text('解除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    provider.selectedAssets = [];
  }

  @override
  Widget bottomActionBar(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (_, _) {
        final bottomPadding = MediaQuery.paddingOf(context).bottom;
        final hasSelection = provider.isSelectedNotEmpty;
        final children = <Widget>[
          if (isPermissionLimited) accessLimitedBottomTip(context),
          Container(
            height: bottomActionBarHeight + bottomPadding,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
            ).copyWith(bottom: bottomPadding),
            color: theme.bottomAppBarTheme.color,
            child: Row(
              children: [
                previewButton(context),
                const Spacer(),
                if (hasSelection)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsetsDirectional.only(end: 12),
                    ),
                    onPressed: () => _clearAllSelections(context),
                    icon: const Icon(Icons.deselect_outlined, size: 18),
                    label: const Text('全解除'),
                  ),
                confirmButton(context),
              ],
            ),
          ),
        ];
        return Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }

  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    // WeChat Momentモードは標準の実装を使用
    if (isWeChatMoment) {
      return super.viewAsset(context, index, currentAsset);
    }
    final p = context.read<DefaultAssetPickerProvider>();
    if (!p.selectedAssets.contains(currentAsset) && p.selectedMaximumAssets) {
      return;
    }
    final revert = effectiveShouldRevertGrid(context);
    final List<AssetEntity> current;
    final int effectiveIndex;
    final selected = p.selectedAssets;
    if (index == null) {
      final list = revert
          ? p.selectedAssets.reversed.toList(growable: false)
          : List<AssetEntity>.from(p.selectedAssets);
      effectiveIndex = list.indexOf(currentAsset);
      current = list;
    } else {
      current = p.currentAssets;
      effectiveIndex = revert ? current.length - index - 1 : index;
    }
    if (current.isEmpty) return;
    final viewerProvider = AssetPickerViewerProvider<AssetEntity>(
      selected,
      maxAssets: p.maxAssets,
    );
    final result = await AssetPickerViewer.pushToViewerWithDelegate(
      context,
      delegate: _WideSelectViewerDelegate(
        currentIndex: effectiveIndex.clamp(0, current.length - 1),
        previewAssets: current,
        themeData: theme,
        previewThumbnailSize: previewThumbnailSize,
        selectPredicate: selectPredicate,
        selectedAssets: selected,
        selectorProvider: p,
        maxAssets: p.maxAssets,
        shouldReversePreview: revert,
        shouldAutoplayPreview: shouldAutoplayPreview,
        provider: viewerProvider,
      ),
      useRootNavigator: viewerUseRootNavigator,
      pageRouteSettings: viewerPageRouteSettings,
      pageRouteBuilder: viewerPageRouteBuilder,
    );
    if (result != null && context.mounted) {
      Navigator.maybeOf(context)?.maybePop(result);
    }
  }
}
