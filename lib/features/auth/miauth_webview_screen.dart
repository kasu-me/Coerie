import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/models/user_model.dart';

const _permissions = [
  'read:account',
  'write:account',
  'read:notifications',
  'write:notifications',
  'read:reactions',
  'write:reactions',
  'write:notes',
  'read:following',
  'write:following',
  'read:drive',
  'write:drive',
  'read:mutes',
  'write:mutes',
  'read:blocks',
  'write:blocks',
  'write:report-abuse',
  'write:votes',
];

/// MiAuth をアプリ内 WebView で完結させる画面。
/// 認証成功時は `({String token, UserModel user})` を pop で返す。
/// キャンセル時は null を返す。
class MiAuthWebViewScreen extends StatefulWidget {
  final String host;

  const MiAuthWebViewScreen({super.key, required this.host});

  @override
  State<MiAuthWebViewScreen> createState() => _MiAuthWebViewScreenState();
}

class _MiAuthWebViewScreenState extends State<MiAuthWebViewScreen> {
  late final WebViewController _controller;
  late final String _sessionId;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();

    // Uri.https の queryParameters は値をパーセントエンコードするため、
    // permission の ':' ',' がエンコードされて Misskey に認識されない問題を回避する。
    // 公式ドキュメントの例に倣い Uri.parse で手動構築する。
    final permStr = _permissions.join(',');
    final authUrl = Uri.parse(
      'https://${widget.host}/miauth/$_sessionId'
      '?name=Coerie'
      '&callback=${Uri.encodeComponent('coerie://auth')}'
      '&permission=$permStr',
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            if (mounted && !_isProcessing) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('読み込みエラー: ${error.description}')),
              );
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme == 'coerie' && uri.host == 'auth') {
              // Deep Link を受信 → セッションチェック
              _checkSession();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(authUrl);
  }

  Future<void> _checkSession() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final dio = Dio();
      final res = await dio.post(
        'https://${widget.host}/api/miauth/$_sessionId/check',
      );
      final data = res.data as Map<String, dynamic>;

      if (data['ok'] != true) {
        throw Exception('認証に失敗しました');
      }

      final token = data['token'] as String;
      final user = UserModel.fromJson(
        data['user'] as Map<String, dynamic>,
        host: widget.host,
      );

      if (mounted) {
        Navigator.of(context).pop((token: token, user: user));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '認証エラー: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading && !_isProcessing) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
