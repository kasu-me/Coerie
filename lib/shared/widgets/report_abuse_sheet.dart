import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/misskey_api_provider.dart';

/// ユーザー通報フォームのボトムシート。
///
/// [userId]      : 通報対象ユーザーの ID
/// [initialComment] : 通報理由の初期値 (省略時は空文字)
class ReportAbuseSheet extends ConsumerStatefulWidget {
  final String userId;
  final String initialComment;

  const ReportAbuseSheet({
    super.key,
    required this.userId,
    this.initialComment = '',
  });

  @override
  ConsumerState<ReportAbuseSheet> createState() => _ReportAbuseSheetState();
}

class _ReportAbuseSheetState extends ConsumerState<ReportAbuseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _commentController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    setState(() => _isSubmitting = true);
    try {
      await api.reportAbuse(widget.userId, _commentController.text.trim());
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通報を送信しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('通報の送信に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('通報', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _commentController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '通報理由を入力してください',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return '通報理由を入力してください';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('送信'),
            ),
          ],
        ),
      ),
    );
  }
}
