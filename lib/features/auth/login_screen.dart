import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../shared/providers/account_provider.dart';
import '../../data/models/account_model.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  String _normalizeHost(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');
  }

  Future<void> _startMiAuth() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final host = _normalizeHost(_hostController.text);

    // TODO: MiAuth フローを実装
    // 1. UUID を生成してセッションIDとする
    // 2. ブラウザで https://{host}/miauth/{sessionId}?name=Coerie&permission=read:account,write:notes,... を開く
    // 3. ユーザーが認証したら https://{host}/api/miauth/{sessionId}/check にPOSTしてトークン取得
    // 4. トークンでユーザー情報取得して AccountModel を保存

    // 開発用: ダミーアカウントを追加
    await ref
        .read(accountProvider.notifier)
        .addAccount(
          AccountModel(
            id: const Uuid().v4(),
            host: host,
            token: 'dummy_token',
            userId: 'dummy_user_id',
            username: 'user',
            name: 'ユーザー',
            isActive: true,
          ),
        );

    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Coerie',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Misskey クライアント',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 48),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'サーバー URL',
                    hintText: 'misskey.io',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onFieldSubmitted: (_) => _startMiAuth(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'サーバーのURLを入力してください';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _startMiAuth,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ログイン'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
