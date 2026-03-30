import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
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
];

class MiAuthService {
  MiAuthService._();

  static const _callbackScheme = 'coerie';
  static const _callbackHost = 'auth';
  static const _prefKeySession = 'miauth_pending_session';
  static const _prefKeyHost = 'miauth_pending_host';

  // アプリが OOM Kill されてディープリンクで再起動した際に
  // main() が handleDeepLink() を呼ぶより先に authenticate() が
  // 実行されることを防ぐため、static で状態を保持する。
  static Completer<Uri>? _pendingCompleter;
  static Uri? _bufferedUri;

  /// main.dart や uriLinkStream から呼び出す。
  static void handleDeepLink(Uri uri) {
    if (uri.scheme != _callbackScheme || uri.host != _callbackHost) return;
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(uri);
    } else {
      // authenticate() がまだ実行されていない場合はバッファリング
      _bufferedUri = uri;
    }
  }

  /// バッファに未処理のコールバックURIがある場合 true。
  static bool get hasPendingCallback => _bufferedUri != null;

  /// MiAuth フローを開始する。
  static Future<({String token, UserModel user})> authenticate(
    String host,
  ) async {
    final sessionId = const Uuid().v4();
    final permStr = _permissions.join(',');
    final authUrl = Uri.https(host, '/miauth/$sessionId', {
      'name': 'Coerie',
      'icon':
          'https://raw.githubusercontent.com/placeholder/coerie/main/assets/icon.png',
      'callback': '$_callbackScheme://$_callbackHost',
      'permission': permStr,
    });

    // OOM Kill による再起動に備えてセッション情報を保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySession, sessionId);
    await prefs.setString(_prefKeyHost, host);

    // ブラウザを開く
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await prefs.remove(_prefKeySession);
      await prefs.remove(_prefKeyHost);
      throw Exception('ブラウザを開けませんでした');
    }

    // ディープリンクを待つ Completer をセット
    _pendingCompleter = Completer<Uri>();

    // アプリがバックグラウンドで生きている場合は uriLinkStream で受信
    final appLinks = AppLinks();
    late StreamSubscription<Uri> sub;
    sub = appLinks.uriLinkStream.listen((uri) {
      handleDeepLink(uri);
      sub.cancel();
    });

    try {
      await _pendingCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          sub.cancel();
          throw TimeoutException('認証がタイムアウトしました');
        },
      );
    } finally {
      _pendingCompleter = null;
    }

    return _checkSession(host, sessionId, prefs);
  }

  /// OOM Kill 後にアプリがディープリンクで再起動した場合に認証を再開する。
  /// 未処理のコールバックがなければ null を返す。
  static Future<({String token, UserModel user, String host})?> tryResumeAuth() async {
    if (_bufferedUri == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_prefKeySession);
    final host = prefs.getString(_prefKeyHost);

    if (sessionId == null || host == null) {
      _bufferedUri = null;
      return null;
    }

    _bufferedUri = null;

    try {
      final result = await _checkSession(host, sessionId, prefs);
      return (token: result.token, user: result.user, host: host);
    } catch (_) {
      return null;
    }
  }

  static Future<({String token, UserModel user})> _checkSession(
    String host,
    String sessionId,
    SharedPreferences prefs,
  ) async {
    final dio = Dio();
    try {
      final res =
          await dio.post('https://$host/api/miauth/$sessionId/check');
      final data = res.data as Map<String, dynamic>;

      await prefs.remove(_prefKeySession);
      await prefs.remove(_prefKeyHost);

      if (data['ok'] != true) throw Exception('認証に失敗しました');

      final token = data['token'] as String;
      final user = UserModel.fromJson(
        data['user'] as Map<String, dynamic>,
        host: host,
      );
      return (token: token, user: user);
    } catch (e) {
      await prefs.remove(_prefKeySession);
      await prefs.remove(_prefKeyHost);
      rethrow;
    }
  }
}
