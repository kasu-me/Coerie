import 'package:coerie/data/models/user_model.dart';
import 'package:coerie/shared/providers/custom_emoji_provider.dart';
import 'package:coerie/shared/widgets/user_name_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 名前表示のテスト。
///
/// 絵文字が解決できた場合は CachedNetworkImage がキャッシュ（path_provider）に
/// 触れてテスト環境では失敗するため、ここでは解決できないケースと
/// モデルのパースだけを確かめる。
void main() {
  UserModel userFromJson(Map<String, dynamic> extra) => UserModel.fromJson({
    'id': 'u1',
    'username': 'alice',
    ...extra,
  });

  group('UserModel.emojis', () {
    test('Map 形式の emojis を読み込む', () {
      final user = userFromJson({
        'name': ':blobcat: Alice',
        'emojis': {'blobcat': 'https://example.com/blobcat.png'},
      });
      expect(user.emojis, {'blobcat': 'https://example.com/blobcat.png'});
    });

    test('リスト形式の emojis を読み込む', () {
      final user = userFromJson({
        'emojis': [
          {'name': 'blobcat', 'url': 'https://example.com/blobcat.png'},
        ],
      });
      expect(user.emojis, {'blobcat': 'https://example.com/blobcat.png'});
    });

    test('emojis が無ければ空', () {
      expect(userFromJson({}).emojis, isEmpty);
    });
  });

  group('UserNameText', () {
    Future<void> pump(WidgetTester tester, UserModel user) {
      return tester.pumpWidget(
        ProviderScope(
          // 実際のプロバイダーはアカウント（Hive）と API に依存するため差し替える
          overrides: [customEmojiUrlMapProvider.overrideWithValue(const {})],
          child: MaterialApp(home: Scaffold(body: UserNameText(user))),
        ),
      );
    }

    testWidgets('解決できない絵文字はショートコードのまま表示する', (tester) async {
      await pump(tester, userFromJson({'name': ':unknown: Alice'}));
      expect(find.text(':unknown: Alice', findRichText: true), findsOneWidget);
    });

    testWidgets('絵文字以外の MFM 記法は解釈しない', (tester) async {
      await pump(tester, userFromJson({'name': '**Alice**'}));
      expect(find.text('**Alice**', findRichText: true), findsOneWidget);
    });

    testWidgets('名前が空ならユーザー名を表示する', (tester) async {
      await pump(tester, userFromJson({'name': ''}));
      expect(find.text('alice', findRichText: true), findsOneWidget);
    });
  });
}
