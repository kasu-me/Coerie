import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../shared/providers/account_provider.dart';
import '../../data/models/account_model.dart';
import 'miauth_webview_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool addAccount;

  const LoginScreen({super.key, this.addAccount = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

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

  Future<void> _startLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final host = _normalizeHost(_hostController.text);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // アプリ内 WebView で MiAuth 認証を行う（外部ブラウザ不要）
      final result = await Navigator.of(context)
          .push<({String token, dynamic user})>(
            MaterialPageRoute(builder: (_) => MiAuthWebViewScreen(host: host)),
          );

      if (result == null) {
        // ユーザーがキャンセル
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await ref
          .read(accountProvider.notifier)
          .addAccount(
            AccountModel(
              id: const Uuid().v4(),
              host: host,
              token: result.token,
              userId: result.user.id,
              username: result.user.username,
              name: result.user.name,
              avatarUrl: result.user.avatarUrl,
              isActive: true,
            ),
          );

      if (mounted) {
        if (widget.addAccount) {
          // アカウント追加時は元の画面に戻る
          context.pop();
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
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
                    hintText: 'misskey.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onFieldSubmitted: (_) => _startLogin(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'サーバーのURLを入力してください';
                    }
                    return null;
                  },
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _startLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ログイン'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'サーバーの認証ページをアプリ内で開きます。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
