import 'dart:io';

import 'package:dio/dio.dart';

/// そのまま画面に出せる日本語メッセージを持つ、アプリ内で投げる例外。
///
/// `Exception('...')` を直接投げると `toString()` に `Exception: ` が付き、
/// 各画面で剥がして回る必要があった。ユーザーに見せる文言はこの型で投げ、
/// 表示側は [apiErrorMessage] を通すこと。
class AppException implements Exception {
  final String message;

  const AppException(this.message);

  @override
  String toString() => message;
}

/// 原因を特定できなかったときの既定メッセージ。
///
/// 例外の `toString()`（英語の内部メッセージ）を画面に出さないための最後の受け皿。
const String defaultApiErrorMessage = '通信に失敗しました。時間をおいて再試行してください';

/// ネットワーク未接続（機内モード・圏外など）の案内。
const String _networkMessage = 'ネットワークに接続できません。通信環境を確認してください';

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

  // クリップ
  'NO_SUCH_CLIP': 'クリップが見つかりませんでした',
  'ALREADY_FAVORITED': 'すでにお気に入りに登録されています',
  'NOT_FAVORITED': 'お気に入りに登録されていません',

  // ノート・ユーザー
  'NO_SUCH_NOTE': 'ノートが見つかりませんでした',
  'NO_SUCH_USER': 'ユーザーが見つかりませんでした',
  'YOU_HAVE_BEEN_BLOCKED': '相手にブロックされているため操作できません',

  // ページ
  'NO_SUCH_PAGE': 'ページが見つかりませんでした',
  'NAME_ALREADY_EXISTS': 'そのページ名（URL）は既に使われています',
  'YOUR_PAGE': '自分のページにはいいねできません',

  // ギャラリー
  'NO_SUCH_POST': '投稿が見つかりませんでした',
  'YOUR_POST': '自分の投稿にはいいねできません',

  // ページ・ギャラリー共通
  'ALREADY_LIKED': 'すでにいいねしています',
  'NOT_LIKED': 'いいねしていません',
  'NO_SUCH_FILE': 'ファイルが見つかりませんでした',
  'ACCESS_DENIED': 'この操作は許可されていません',
};

/// 「拒否」ではあるが権限スコープ不足ではないエラーコード。
/// 再認証しても解決しないため [isPermissionError] では false にする。
const Set<String> _nonScopeDenialCodes = {
  'ACCESS_DENIED',
  'YOUR_PAGE',
  'YOUR_POST',
  'YOU_HAVE_BEEN_BLOCKED',
  'YOUR_ACCOUNT_SUSPENDED',
};

/// 権限不足時の案内。アプリが要求する権限は認証時に確定するため、
/// 権限を追加した後は再認証しないと反映されない点を伝える。
const String _permissionMessage =
    '権限が不足しているため実行できません。「アカウント設定」→「トークンを再取得」からアカウントを登録し直してください。';

/// 通信・API エラーをユーザー向けの日本語メッセージに変換する。
///
/// 判別できないエラーは [fallback]（例: `'投票に失敗しました'`）を返す。
/// 例外の `toString()` をそのまま画面に出すと英語の内部メッセージが露出するため、
/// エラーを表示する箇所は必ずこの関数を通すこと。
String apiErrorMessage(
  Object error, {
  String fallback = defaultApiErrorMessage,
}) {
  // ユーザー向けの文言を持つ例外はそのまま見せる。
  if (error is AppException) return error.message;
  if (error is! DioException) return fallback;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'サーバーの応答がありません。時間をおいて再試行してください';
    case DioExceptionType.connectionError:
      return _networkMessage;
    case DioExceptionType.badCertificate:
      return 'サーバーの証明書を検証できませんでした';
    case DioExceptionType.cancel:
      return fallback;
    case DioExceptionType.unknown:
      // 機内モードや名前解決の失敗は type が unknown のまま
      // SocketException を包んで届くことがある。
      if (error.error is SocketException) return _networkMessage;
      return fallback;
    case DioExceptionType.badResponse:
      break;
  }

  final res = error.response;
  final code = _apiErrorOf(error)?['code'] as String?;
  final known = _messageByCode[code];
  if (known != null) return known;

  if (isPermissionError(error)) return _permissionMessage;

  final status = res?.statusCode ?? 0;
  if (status == 429) return _messageByCode['RATE_LIMIT_EXCEEDED']!;
  if (status >= 500) return 'サーバーでエラーが発生しました。時間をおいて再試行してください';

  return fallback;
}

/// アプリが要求する権限スコープの不足が原因のエラーかを判定する。
///
/// アクセストークンの権限は認証時に確定するため、アプリ側で権限を追加しても
/// 既存ユーザーのトークンは古い権限のままになる。このエラーを検出したら
/// MiAuth の再認証（アカウント設定 →「トークンを再取得」）を促すこと。
///
/// `ACCESS_DENIED`（他人のページ・投稿の編集）や `YOUR_PAGE` のような、
/// 再認証しても解決しない拒否は false を返す。
bool isPermissionError(Object error) {
  if (error is! DioException) return false;
  if (error.type != DioExceptionType.badResponse) return false;

  final apiError = _apiErrorOf(error);
  final code = apiError?['code'] as String?;
  if (code == 'PERMISSION_DENIED' || code == 'CREDENTIAL_REQUIRED') return true;
  if (code != null && _nonScopeDenialCodes.contains(code)) return false;

  if (apiError?['kind'] == 'permission') return true;

  final status = error.response?.statusCode ?? 0;
  return status == 401 || status == 403;
}

Map<String, dynamic>? _apiErrorOf(DioException error) {
  final data = error.response?.data;
  if (data is! Map<String, dynamic>) return null;
  return data['error'] as Map<String, dynamic>?;
}
