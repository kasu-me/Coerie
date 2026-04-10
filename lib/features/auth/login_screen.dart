import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/account_visibility_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../data/models/account_model.dart';
import '../../data/models/app_settings_model.dart';
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

  Future<void> _importFromFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ファイル選択に失敗しました: $e')));
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    final path = result.files.first.path;
    String jsonStr;
    try {
      if (bytes != null) {
        jsonStr = utf8.decode(bytes);
      } else if (path != null) {
        jsonStr = await File(path).readAsString();
      } else {
        throw const FormatException('ファイルを読み込めませんでした');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ファイルの読み込みに失敗しました: $e')));
      }
      return;
    }

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = decoded['version'] as int? ?? 1;

      // グローバル設定のインポート
      if (version >= 2) {
        final globalJson =
            decoded['globalSettings'] as Map<String, dynamic>? ?? decoded;
        final importedSettings = AppSettingsModel.fromJson(globalJson);
        await ref
            .read(settingsProvider.notifier)
            .importSettings(importedSettings);
      } else {
        final importedSettings = AppSettingsModel.fromJson(decoded);
        await ref
            .read(settingsProvider.notifier)
            .importSettings(importedSettings);
      }

      // アカウント情報のインポート（バージョン3のみ）
      int importedCount = 0;
      if (version >= 3) {
        final accountsJson = decoded['accounts'] as List<dynamic>?;
        if (accountsJson != null) {
          final importedAccounts = accountsJson
              .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
              .toList();
          await ref
              .read(accountProvider.notifier)
              .importAccounts(importedAccounts);
          importedCount = importedAccounts.length;
        }

        // アカウント別設定のインポート
        final accountSettingsMap =
            decoded['accountSettings'] as Map<String, dynamic>? ?? {};
        for (final entry in accountSettingsMap.entries) {
          final accountId = entry.key;
          final data = entry.value as Map<String, dynamic>;

          final tabsJson = data['tabs'] as List<dynamic>?;
          if (tabsJson != null) {
            final tabs = tabsJson
                .map((e) => TabConfigModel.fromJson(e as Map<String, dynamic>))
                .toList();
            await ref
                .read(accountTabsProvider(accountId).notifier)
                .setTabs(tabs);
          }

          final visibility = data['defaultVisibility'] as String?;
          if (visibility != null) {
            await ref
                .read(accountVisibilityProvider(accountId).notifier)
                .setVisibility(visibility);
          }
        }
      }

      if (!mounted) return;

      if (importedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定をインポートしました（アカウント $importedCount 件）')),
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '設定をインポートしました。アカウント情報は含まれていませんでした。'
              'ログインするにはアクセストークンを含む設定ファイルが必要です。',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('無効なJSONです: ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
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
              if (!widget.addAccount) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'または',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: _isLoading ? null : _importFromFile,
                    label: const Text('設定ファイルからインポート'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'アクセストークンを含む設定ファイルからアカウントを復元します。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
