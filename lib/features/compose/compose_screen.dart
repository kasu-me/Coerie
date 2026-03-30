import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/providers/account_provider.dart';
import '../../core/constants/app_constants.dart';
import '../draft/draft_provider.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  final String? draftId;

  const ComposeScreen({super.key, this.draftId});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _textController;
  String _visibility = AppConstants.visibilityPublic;
  String? _currentDraftId;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _currentDraftId = widget.draftId;

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

  Future<void> _post() async {
    if (_textController.text.trim().isEmpty || _isOverLimit) return;

    // TODO: 実際のAPI投稿処理
    // final account = ref.read(activeAccountProvider);
    // await dio.post('https://${account.host}/api/notes/create', data: {
    //   'i': account.token,
    //   'text': _textController.text,
    //   'visibility': _visibility,
    // });

    if (_currentDraftId != null) {
      await ref.read(draftProvider.notifier).deleteDraft(_currentDraftId!);
    }
    if (mounted) context.pop();
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
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEmojiPicker() {
    // TODO: サーバーのカスタム絵文字を取得して表示
    showModalBottomSheet(
      context: context,
      builder: (_) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('絵文字ピッカーは今後実装予定です'),
        ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText: '何かつぶやく...',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
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
                // アカウントアイコン
                GestureDetector(
                  onTap: () {
                    // TODO: アカウント切り替え
                  },
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
                  onPressed: _textController.text.trim().isEmpty || _isOverLimit
                      ? null
                      : _post,
                  child: const Text('投稿'),
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
                // メディア添付
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: 'メディアを添付',
                  onPressed: () {
                    // TODO: image_picker で画像選択
                  },
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
                  onPressed: _showEmojiPicker,
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
