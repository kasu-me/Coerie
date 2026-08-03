import 'package:dio/dio.dart';

/// Misskey API のエラーコードに対応する日本語メッセージ。
/// ここに無いコードは HTTP ステータス・`kind` からの推測、
/// それでも判別できなければ呼び出し元の fallback を使う。
const Map<String, String> _messageByCode = {
  // 認証・権限
  'PERMISSION_DENIED': _permissionMessage,
  'CREDENTIAL_REQUIRED': _permissionMessage,
  'AUTHENTICATION_FAILED': 'ログイン情報が無効です。アカウントを登録し直してください',
  'YOUR_ACCOUNT_SUSPENDED': 'このアカウントは凍結されています',
  'RATE_LIMIT_EXCEEDED': '操作が多すぎます。しばらく待ってから再試行してください',

  // 投票
  'NO_POLL': 'このノートには投票がありません',
  'INVALID_CHOICE': '選択肢が正しくありません',
  'ALREADY_VOTED': 'すでに投票済みです',
  'ALREADY_EXPIRED': '投票は締め切られています',

  // ノート・ユーザー
  'NO_SUCH_NOTE': 'ノートが見つかりませんでした',
  'NO_SUCH_USER': 'ユーザーが見つかりませんでした',
  'YOU_HAVE_BEEN_BLOCKED': '相手にブロックされているため操作できません',
};

/// 権限不足時の案内。アプリが要求する権限は認証時に確定するため、
/// 権限を追加した後は再認証しないと反映されない点を伝える。
const String _permissionMessage =
    '権限が不足しているため実行できません。「アカウント設定」→「トークンを再取得」からアカウントを登録し直してください。';

/// 通信・API エラーをユーザー向けの日本語メッセージに変換する。
///
/// 判別できないエラーは [fallback]（例: `'投票に失敗しました'`）を返す。
String apiErrorMessage(Object error, {required String fallback}) {
  if (error is! DioException) return fallback;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'サーバーの応答がありません。時間をおいて再試行してください';
    case DioExceptionType.connectionError:
      return 'ネットワークに接続できません。通信環境を確認してください';
    case DioExceptionType.badCertificate:
      return 'サーバーの証明書を検証できませんでした';
    case DioExceptionType.cancel:
      return fallback;
    case DioExceptionType.unknown:
      return fallback;
    case DioExceptionType.badResponse:
      break;
  }

  final res = error.response;
  final data = res?.data;
  final apiError = data is Map<String, dynamic>
      ? data['error'] as Map<String, dynamic>?
      : null;

  final code = apiError?['code'] as String?;
  final known = _messageByCode[code];
  if (known != null) return known;

  if (apiError?['kind'] == 'permission') return _permissionMessage;

  final status = res?.statusCode ?? 0;
  if (status == 401 || status == 403) return _permissionMessage;
  if (status == 429) return _messageByCode['RATE_LIMIT_EXCEEDED']!;
  if (status >= 500) return 'サーバーでエラーが発生しました。時間をおいて再試行してください';

  return fallback;
}
