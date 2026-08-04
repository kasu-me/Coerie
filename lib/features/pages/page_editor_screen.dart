import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/cache_service.dart';
import '../../data/models/note_model.dart';
import '../../data/models/page_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'providers/pages_provider.dart';
import 'widgets/page_list_tile.dart';

/// ページの新規作成・編集画面（`/pages/new`、`/pages/:pageId/edit`）。
///
/// **`pages/create` はレート制限が 10回/時**と厳しいため、
/// 作成は1回だけ行い、成功後は [_pageId] を保持して以降の保存を
/// `pages/update`（300回/時）に切り替える。
///
/// MVP の割り切り:
/// - セクションの入れ子は1階層まで（セクションの中にセクションは作れない）
/// - 並べ替えはドラッグではなく上下移動ボタン
/// - `variables` / `script` は UI に出さず、読み込んだ値を保持して往復させる
class PageEditorScreen extends ConsumerStatefulWidget {
  /// 編集対象のページID。null なら新規作成。
  final String? pageId;

  /// 一覧・閲覧画面から渡された編集対象。null かつ [pageId] があれば自前で取得する。
  final PageModel? initialPage;

  const PageEditorScreen({super.key, this.pageId, this.initialPage});

  @override
  ConsumerState<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends ConsumerState<PageEditorScreen> {
  final _titleController = TextEditingController();
  final _nameController = TextEditingController();
  final _summaryController = TextEditingController();

  /// 作成済みページのID。null の間だけ `pages/create` を使う。
  String? _pageId;

  String _font = 'sans-serif';
  bool _alignCenter = false;
  bool _hideTitleWhenPinned = false;

  /// 廃止済み機能の値。UI には出さないが往復で失わないよう保持する。
  List<dynamic> _variables = const [];
  String _script = '';

  String? _eyeCatchFileId;
  String? _eyeCatchUrl;

  /// 既存のアイキャッチを消す操作をしたか（update 時に null 送信が必要）。
  bool _eyeCatchRemoved = false;

  List<_EditBlock> _blocks = [];

  bool _isLoading = false;
  bool _isSaving = false;
  Object? _loadError;
  bool _dirty = false;

  bool get _isEditing => _pageId != null;

  @override
  void initState() {
    super.initState();
    _pageId = widget.pageId;
    final initial = widget.initialPage;
    if (initial != null) {
      _applyPage(initial);
    } else if (widget.pageId != null) {
      _load();
    } else {
      _initNewPage();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _summaryController.dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  void _initNewPage() {
    // name はユーザー内でユニーク。手入力させると必ず衝突するため自動生成する。
    _nameController.text =
        'page-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    _blocks = [_EditBlock.create('text')];
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    final pageId = widget.pageId;
    if (api == null || pageId == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final page = await api.getPage(pageId: pageId);
      if (!mounted) return;
      setState(() => _applyPage(page));
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyPage(PageModel page) {
    _pageId = page.id;
    _titleController.text = page.title;
    _nameController.text = page.name;
    _summaryController.text = page.summary ?? '';
    _font = page.font == 'serif' ? 'serif' : 'sans-serif';
    _alignCenter = page.alignCenter;
    _hideTitleWhenPinned = page.hideTitleWhenPinned;
    _variables = page.variables;
    _script = page.script;
    _eyeCatchFileId = page.eyeCatchingImageId ?? page.eyeCatchingImage?.id;
    _eyeCatchUrl = page.eyeCatchingImage?.url;
    _eyeCatchRemoved = false;

    final urlById = page.fileById.map((k, v) => MapEntry(k, v.url));
    for (final b in _blocks) {
      b.dispose();
    }
    _blocks = page.content.map((b) => _EditBlock.from(b, urlById)).toList();
    _dirty = false;
  }

  void _markDirty() => _dirty = true;

  // ---- ブロック操作 ----

  /// [parent] が null ならトップレベル、そうでなければそのセクションの子に追加する。
  Future<void> _addBlock({_EditBlock? parent}) async {
    final allowSection = parent == null; // 入れ子は1階層まで
    final type = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('ブロックを追加')),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('テキスト'),
              subtitle: const Text('MFM が使えます'),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
            if (allowSection)
              ListTile(
                leading: const Icon(Icons.title),
                title: const Text('セクション（見出し）'),
                subtitle: const Text('中にブロックをまとめられます'),
                onTap: () => Navigator.pop(ctx, 'section'),
              ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('画像'),
              subtitle: const Text('ドライブから選択します'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('ノート埋め込み'),
              subtitle: const Text('ノートIDを指定します'),
              onTap: () => Navigator.pop(ctx, 'note'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() {
      final block = _EditBlock.create(type);
      if (parent == null) {
        _blocks.add(block);
      } else {
        parent.children.add(block);
      }
      _markDirty();
    });
  }

  void _moveBlock(List<_EditBlock> list, int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= list.length) return;
    setState(() {
      final b = list.removeAt(index);
      list.insert(next, b);
      _markDirty();
    });
  }

  Future<void> _removeBlock(List<_EditBlock> list, int index) async {
    final ok = await confirmAction(
      context,
      ref,
      title: 'ブロックを削除',
      message: 'このブロックを削除しますか？',
      confirmLabel: '削除',
    );
    if (!ok || !mounted) return;
    setState(() {
      list.removeAt(index).dispose();
      _markDirty();
    });
  }

  /// ドライブから画像を1件選ぶ。キャンセル時は null。
  Future<DriveFileModel?> _pickDriveImage() async {
    final selected = await context.push<List<DriveFileModel>>(
      '/drive',
      extra: {'selectionMode': true, 'maxSelection': 1},
    );
    if (selected == null || selected.isEmpty) return null;
    return selected.first;
  }

  Future<void> _pickEyeCatch() async {
    final file = await _pickDriveImage();
    if (file == null || !mounted) return;
    setState(() {
      _eyeCatchFileId = file.id;
      _eyeCatchUrl = file.url;
      _eyeCatchRemoved = false;
      _markDirty();
    });
  }

  void _removeEyeCatch() {
    setState(() {
      _eyeCatchFileId = null;
      _eyeCatchUrl = null;
      _eyeCatchRemoved = true;
      _markDirty();
    });
  }

  Future<void> _pickBlockImage(_EditBlock block) async {
    final file = await _pickDriveImage();
    if (file == null || !mounted) return;
    setState(() {
      block.fileId = file.id;
      block.fileUrl = file.url;
      _markDirty();
    });
  }

  // ---- 保存・削除 ----

  String? _validate() {
    if (_titleController.text.trim().isEmpty) return 'タイトルを入力してください';
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'URL（ページ名）を入力してください';
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
      return 'URLには半角英数字・ハイフン・アンダースコアのみ使えます';
    }
    return null;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    final title = _titleController.text.trim();
    final name = _nameController.text.trim();
    final summary = _summaryController.text.trim();
    final content = _blocks.map((b) => b.toBlock()).toList();

    setState(() => _isSaving = true);
    try {
      final pageId = _pageId;
      if (pageId == null) {
        // pages/create は 10回/時。ここを通るのは1ページにつき1回だけ。
        final created = await api.createPage(
          title: title,
          name: name,
          content: content,
          summary: summary.isEmpty ? null : summary,
          font: _font,
          alignCenter: _alignCenter,
          hideTitleWhenPinned: _hideTitleWhenPinned,
          eyeCatchingImageId: _eyeCatchFileId,
          variables: _variables,
          script: _script,
        );
        if (!mounted) return;
        // 以降の保存は update に切り替える（再作成を絶対に発生させない）
        setState(() {
          _pageId = created.id;
          _dirty = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ページを作成しました')));
      } else {
        await api.updatePage(
          pageId: pageId,
          title: title,
          name: name,
          summary: summary.isEmpty ? null : summary,
          clearSummary: summary.isEmpty,
          content: content,
          font: _font,
          alignCenter: _alignCenter,
          hideTitleWhenPinned: _hideTitleWhenPinned,
          eyeCatchingImageId: _eyeCatchFileId,
          clearEyeCatchingImage: _eyeCatchRemoved && _eyeCatchFileId == null,
          variables: _variables,
          script: _script,
        );
        if (!mounted) return;
        setState(() {
          _dirty = false;
          _eyeCatchRemoved = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ページを保存しました')));
      }
      if (!mounted) return;
      final accountKey = ref.read(activeAccountProvider)?.id ?? '';
      ref.read(myPagesProvider(accountKey).notifier).refresh();
    } catch (e) {
      if (mounted) showApiErrorSnackBar(context, e, fallback: 'ページの保存に失敗しました');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final pageId = _pageId;
    final api = ref.read(misskeyApiProvider);
    if (pageId == null || api == null) return;

    final ok = await confirmAction(
      context,
      ref,
      title: 'ページを削除',
      message: '「${_titleController.text.trim()}」を削除しますか？この操作は取り消せません。',
      confirmLabel: '削除',
    );
    if (!ok || !mounted) return;

    try {
      await api.deletePage(pageId);
      if (!mounted) return;
      final accountKey = ref.read(activeAccountProvider)?.id ?? '';
      ref.read(myPagesProvider(accountKey).notifier).removeLocally(pageId);
      _dirty = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ページを削除しました')));
      context.pop();
    } catch (e) {
      if (mounted) showApiErrorSnackBar(context, e, fallback: 'ページの削除に失敗しました');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmAction(
      context,
      ref,
      title: '編集を破棄',
      message: '保存していない変更があります。破棄して戻りますか？',
      confirmLabel: '破棄する',
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // await をまたいで context を使わないよう、先に Navigator を取り出す
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'ページを編集' : 'ページを作成'),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: '保存',
                onPressed: _save,
              ),
            if (_isEditing)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
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
          ],
        ),
        body: SafeArea(bottom: true, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return PagesErrorView(
        error: _loadError,
        message: 'ページの取得に失敗しました',
        onRetry: _load,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        _sectionLabel('基本情報'),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'タイトル',
            prefixIcon: Icon(Icons.title),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'URL（ページ名）',
            helperText: '半角英数字・- ・_ のみ。自分のページ内で重複できません',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _summaryController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '概要（任意）',
            prefixIcon: Icon(Icons.short_text),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),

        const SizedBox(height: 24),
        _sectionLabel('アイキャッチ画像'),
        _buildEyeCatch(),

        const SizedBox(height: 24),
        _sectionLabel('表示設定'),
        Row(
          children: [
            const Icon(Icons.font_download_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'sans-serif',
                    label: Text('ゴシック'),
                    icon: Icon(Icons.text_fields),
                  ),
                  ButtonSegment(
                    value: 'serif',
                    label: Text('明朝'),
                    icon: Icon(Icons.menu_book_outlined),
                  ),
                ],
                selected: {_font},
                onSelectionChanged: (s) => setState(() {
                  _font = s.first;
                  _markDirty();
                }),
              ),
            ),
          ],
        ),
        SwitchListTile(
          value: _alignCenter,
          onChanged: (v) => setState(() {
            _alignCenter = v;
            _markDirty();
          }),
          secondary: const Icon(Icons.format_align_center),
          title: const Text('中央寄せで表示する'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _hideTitleWhenPinned,
          onChanged: (v) => setState(() {
            _hideTitleWhenPinned = v;
            _markDirty();
          }),
          secondary: const Icon(Icons.push_pin_outlined),
          title: const Text('プロフィールにピン留めした時はタイトルを隠す'),
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 24),
        _sectionLabel('本文'),
        if (_blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'ブロックがありません。下のボタンから追加してください。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        for (int i = 0; i < _blocks.length; i++)
          _buildBlockCard(_blocks, i, isChild: false),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('ブロックを追加'),
          onPressed: () => _addBlock(),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _buildEyeCatch() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_eyeCatchUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              cacheManager: AppCacheManager(),
              imageUrl: _eyeCatchUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(
                height: 140,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          )
        else
          Container(
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'アイキャッチ画像は未設定です',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_outlined),
              label: Text(_eyeCatchUrl == null ? 'ドライブから選択' : '画像を変更'),
              onPressed: _pickEyeCatch,
            ),
            if (_eyeCatchUrl != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('削除'),
                onPressed: _removeEyeCatch,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBlockCard(
    List<_EditBlock> list,
    int index, {
    required bool isChild,
  }) {
    final block = list[index];
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(bottom: 12, left: isChild ? 12 : 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(block.icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    block.label,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: '上へ移動',
                  visualDensity: VisualDensity.compact,
                  onPressed: index == 0
                      ? null
                      : () => _moveBlock(list, index, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: '下へ移動',
                  visualDensity: VisualDensity.compact,
                  onPressed: index == list.length - 1
                      ? null
                      : () => _moveBlock(list, index, 1),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '削除',
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.error,
                  onPressed: () => _removeBlock(list, index),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildBlockEditor(block),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockEditor(_EditBlock block) {
    final theme = Theme.of(context);
    switch (block.type) {
      case 'text':
        return TextField(
          controller: block.controller,
          maxLines: null,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: '本文（MFM が使えます）',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        );

      case 'section':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: block.controller,
              decoration: const InputDecoration(
                labelText: '見出し',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < block.children.length; i++)
              _buildBlockCard(block.children, i, isChild: true),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('このセクションにブロックを追加'),
                onPressed: () => _addBlock(parent: block),
              ),
            ),
          ],
        );

      case 'image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.fileUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  cacheManager: AppCacheManager(),
                  imageUrl: block.fileUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    height: 120,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              Text(
                block.fileId == null ? '画像が未選択です' : '選択済みの画像を表示できません',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_outlined),
              label: Text(block.fileId == null ? 'ドライブから選択' : '画像を変更'),
              onPressed: () => _pickBlockImage(block),
            ),
          ],
        );

      case 'note':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: block.controller,
              decoration: const InputDecoration(
                labelText: 'ノートID',
                hintText: '例: 9abcdefghij',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _markDirty(),
            ),
            SwitchListTile(
              value: block.detailed,
              onChanged: (v) => setState(() {
                block.detailed = v;
                _markDirty();
              }),
              title: const Text('詳細表示'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        );

      default:
        // 本アプリが解釈しないブロック。内容は編集できないが保存時に元 JSON を送り返す。
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'このブロックはこのアプリでは編集できません（保存しても内容はそのまま保持されます）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        );
    }
  }
}

// ---- 編集用ブロック ----

/// エディタ上で1ブロックを表す可変オブジェクト。
///
/// [PageBlock] はイミュータブルで [TextEditingController] を持てないため、
/// 編集中はこのクラスで保持し、保存時に [toBlock] で変換する。
class _EditBlock {
  final String id;
  final String type;

  /// サーバーから受け取った元 JSON。未対応フィールドを往復で失わないため保持する。
  final Map<String, dynamic> raw;

  /// text: 本文 / section: 見出し / note: ノートID
  final TextEditingController controller;

  String? fileId;
  String? fileUrl;
  bool detailed;
  final List<_EditBlock> children;

  _EditBlock({
    required this.id,
    required this.type,
    this.raw = const {},
    String initialText = '',
    this.fileId,
    this.fileUrl,
    this.detailed = false,
    List<_EditBlock>? children,
  }) : controller = TextEditingController(text: initialText),
       children = children ?? [];

  static int _seq = 0;

  /// 新規ブロックのIDを作る。ページ内で一意であればよい。
  static String _newId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$_seq';
  }

  factory _EditBlock.create(String type) =>
      _EditBlock(id: _newId(), type: type);

  factory _EditBlock.from(PageBlock block, Map<String, String> urlById) {
    return switch (block) {
      PageTextBlock b => _EditBlock(
        id: b.id,
        type: 'text',
        raw: b.raw,
        initialText: b.text,
      ),
      PageSectionBlock b => _EditBlock(
        id: b.id,
        type: 'section',
        raw: b.raw,
        initialText: b.title,
        children: b.children.map((c) => _EditBlock.from(c, urlById)).toList(),
      ),
      PageImageBlock b => _EditBlock(
        id: b.id,
        type: 'image',
        raw: b.raw,
        fileId: b.fileId,
        fileUrl: b.fileId == null ? null : urlById[b.fileId!],
      ),
      PageNoteBlock b => _EditBlock(
        id: b.id,
        type: 'note',
        raw: b.raw,
        initialText: b.noteId ?? '',
        detailed: b.detailed,
      ),
      PageUnknownBlock b => _EditBlock(id: b.id, type: b.type, raw: b.raw),
    };
  }

  IconData get icon => switch (type) {
    'text' => Icons.notes,
    'section' => Icons.title,
    'image' => Icons.image_outlined,
    'note' => Icons.article_outlined,
    _ => Icons.help_outline,
  };

  String get label => switch (type) {
    'text' => 'テキスト',
    'section' => 'セクション',
    'image' => '画像',
    'note' => 'ノート埋め込み',
    _ => '未対応ブロック（$type）',
  };

  PageBlock toBlock() {
    switch (type) {
      case 'text':
        return PageTextBlock(id: id, text: controller.text, raw: raw);
      case 'section':
        return PageSectionBlock(
          id: id,
          title: controller.text,
          children: children.map((c) => c.toBlock()).toList(),
          raw: raw,
        );
      case 'image':
        return PageImageBlock(id: id, fileId: fileId, raw: raw);
      case 'note':
        final noteId = controller.text.trim();
        return PageNoteBlock(
          id: id,
          noteId: noteId.isEmpty ? null : noteId,
          detailed: detailed,
          raw: raw,
        );
      default:
        return PageUnknownBlock(id: id, type: type, raw: raw);
    }
  }

  void dispose() {
    controller.dispose();
    for (final c in children) {
      c.dispose();
    }
  }
}
