import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
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

  /// MiAuth フローを開始する。
  /// 完了するとアクセストークンを返す。失敗時は例外をスロー。
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

    // ブラウザを開く
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw Exception('ブラウザを開けませんでした');
    }

    // Deep Link でコールバックを待つ
    final appLinks = AppLinks();
    final completer = Completer<Uri>();
    late StreamSubscription sub;

    sub = appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == _callbackScheme && uri.host == _callbackHost) {
        if (!completer.isCompleted) completer.complete(uri);
        sub.cancel();
      }
    });

    // 5分タイムアウト
    await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        sub.cancel();
        throw TimeoutException('認証がタイムアウトしました');
      },
    );

    // セッションチェックでトークン取得
    final dio = Dio();
    final res = await dio.post('https://$host/api/miauth/$sessionId/check');
    final data = res.data as Map<String, dynamic>;

    if (data['ok'] != true) {
      throw Exception('認証に失敗しました');
    }

    final token = data['token'] as String;
    final user = UserModel.fromJson(
      data['user'] as Map<String, dynamic>,
      host: host,
    );

    return (token: token, user: user);
  }
}
