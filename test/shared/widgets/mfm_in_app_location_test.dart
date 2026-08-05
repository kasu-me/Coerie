import 'package:coerie/shared/widgets/mfm_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// ノート内のリンクをアプリ内画面へ振り分ける判定のテスト。
void main() {
  String? locationOf(String url) => inAppLocationOf(Uri.parse(url));

  group('クリップ', () {
    test('クリップURLはホスト付きでクリップ画面へ', () {
      expect(
        locationOf('https://misskey.io/clips/9abc'),
        '/clips/9abc?host=misskey.io',
      );
    });
  });

  group('ギャラリー', () {
    test('ギャラリー投稿URLはホスト付きで詳細画面へ', () {
      expect(
        locationOf('https://misskey.io/gallery/9xyz'),
        '/gallery/9xyz?host=misskey.io',
      );
    });

    test('末尾の余分なセグメントは無視して詳細画面へ', () {
      expect(
        locationOf('https://misskey.io/gallery/9xyz/'),
        '/gallery/9xyz?host=misskey.io',
      );
    });

    test('新規投稿URLは詳細として扱わない', () {
      expect(locationOf('https://misskey.io/gallery/new'), isNull);
    });

    test('ギャラリー一覧URLは詳細として扱わない', () {
      expect(locationOf('https://misskey.io/gallery'), isNull);
    });
  });

  group('ページ', () {
    test('ページURLは name + username 解決ルートへ', () {
      expect(
        locationOf('https://misskey.io/@alice/pages/my-page'),
        '/pages/by-name/alice/my-page?host=misskey.io',
      );
    });

    test('acct にホストが含まれる場合はそのホストを見に行く', () {
      expect(
        locationOf('https://example.com/@alice@misskey.io/pages/my-page'),
        '/pages/by-name/alice/my-page?host=misskey.io',
      );
    });

    test('ページ名にURLで使えない文字があればエスケープする', () {
      expect(
        locationOf('https://misskey.io/@alice/pages/日記 1'),
        '/pages/by-name/alice/%E6%97%A5%E8%A8%98%201?host=misskey.io',
      );
    });

    test('ページ名が無ければアプリ内では開かない', () {
      expect(locationOf('https://misskey.io/@alice/pages'), isNull);
    });

    test('プロフィールURLはアプリ内では開かない', () {
      expect(locationOf('https://misskey.io/@alice'), isNull);
    });
  });

  group('対象外', () {
    test('無関係なURLは null', () {
      expect(locationOf('https://example.com/foo/bar'), isNull);
    });

    test('http/https 以外のスキームは null', () {
      expect(locationOf('coerie://auth/clips/9abc'), isNull);
    });
  });
}
