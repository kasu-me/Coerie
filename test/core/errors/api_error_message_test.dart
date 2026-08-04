import 'dart:io';

import 'package:coerie/core/errors/api_error_message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画面に出すメッセージへ英語の内部エラーが混ざっていないことを確かめる。
void main() {
  final options = RequestOptions(path: 'notes/timeline');

  group('apiErrorMessage', () {
    test('接続エラーはネットワーク未接続の案内になる', () {
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('Network is unreachable'),
        message: 'The connection errored: Network is unreachable',
      );

      final message = apiErrorMessage(error, fallback: 'タイムラインを取得できませんでした');

      expect(message, 'ネットワークに接続できません。通信環境を確認してください');
      expect(message, isNot(contains('DioException')));
      expect(message, isNot(contains('SocketException')));
    });

    test('type が unknown でも SocketException ならネットワーク未接続と判断する', () {
      final error = DioException(
        requestOptions: options,
        error: const SocketException('Failed host lookup'),
      );

      expect(apiErrorMessage(error), 'ネットワークに接続できません。通信環境を確認してください');
    });

    test('タイムアウトは応答なしの案内になる', () {
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );

      expect(apiErrorMessage(error), 'サーバーの応答がありません。時間をおいて再試行してください');
    });

    test('AppException のメッセージはそのまま表示する', () {
      expect(
        apiErrorMessage(
          const AppException('ファイルサイズが大きすぎます'),
          fallback: '失敗しました',
        ),
        'ファイルサイズが大きすぎます',
      );
    });

    test('判別できない例外は fallback を返し、例外の文字列は漏らさない', () {
      expect(
        apiErrorMessage(
          StateError('Bad state: no element'),
          fallback: '取得できませんでした',
        ),
        '取得できませんでした',
      );
    });

    test('fallback 未指定でも既定の日本語メッセージを返す', () {
      expect(apiErrorMessage(Exception('boom')), defaultApiErrorMessage);
    });

    test('API のエラーコードは対応する日本語メッセージになる', () {
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 400,
          data: {
            'error': {'code': 'NO_SUCH_NOTE', 'kind': 'client'},
          },
        ),
      );

      expect(apiErrorMessage(error, fallback: '失敗しました'), 'ノートが見つかりませんでした');
    });

    test('5xx はサーバーエラーの案内になる', () {
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: options, statusCode: 503),
      );

      expect(
        apiErrorMessage(error, fallback: '失敗しました'),
        'サーバーでエラーが発生しました。時間をおいて再試行してください',
      );
    });
  });
}
