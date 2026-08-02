import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:coerie/core/constants/app_constants.dart';
import 'package:coerie/data/local/hive_service.dart';

void main() {
  const accounts = AppConstants.accountsBox;
  const drafts = AppConstants.draftsBox;

  tearDown(HiveService.debugSetStartupState);

  group('consumeStartupIssue は accountsBox 専用', () {
    test('accountsBox を破棄したら accountsReset', () {
      HiveService.debugSetStartupState(reset: const {accounts});

      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.accountsReset,
      );
    });

    test('accountsBox がメモリ上のみなら storageUnavailable', () {
      HiveService.debugSetStartupState(volatile: const {accounts});

      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.storageUnavailable,
      );
    });

    test('draftsBox だけを破棄した場合は通知しない', () {
      HiveService.debugSetStartupState(reset: const {drafts});

      expect(HiveService.consumeStartupIssue(), isNull);
    });

    test('draftsBox だけがメモリ上のみの場合も通知しない', () {
      // ログイン画面の文言は accountsBox が対象である前提なので、
      // drafts 側の問題でこの通知を出すと事実と異なる案内になる。
      HiveService.debugSetStartupState(volatile: const {drafts});

      expect(HiveService.consumeStartupIssue(), isNull);
    });

    test('問題が無ければ null', () {
      HiveService.debugSetStartupState();

      expect(HiveService.consumeStartupIssue(), isNull);
    });
  });

  group('consumeStartupIssue の優先順位', () {
    test('accountsBox がメモリ上のみなら draftsBox の破棄より優先される', () {
      HiveService.debugSetStartupState(
        reset: const {drafts},
        volatile: const {accounts},
      );

      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.storageUnavailable,
      );
    });

    test('同じボックスが両方に入っていたら storageUnavailable が優先される', () {
      // _openBoxSafely は step 3 に落ちる際に reset 側の記録を取り消すため
      // 本来この状態にはならないが、優先順位を固定しておく。
      HiveService.debugSetStartupState(
        reset: const {accounts},
        volatile: const {accounts},
      );

      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.storageUnavailable,
      );
    });
  });

  group('consumeStartupIssue の状態遷移', () {
    test('一度取り出すと2回目以降は null', () {
      HiveService.debugSetStartupState(reset: const {accounts});

      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.accountsReset,
      );
      expect(HiveService.consumeStartupIssue(), isNull);
      expect(HiveService.consumeStartupIssue(), isNull);
    });

    test('取り出してもボックス名の記録は残る', () {
      // 保存操作のフィードバック（compose_screen の _saveDraft）は
      // 通知の取り出し後も isVolatile を参照するため、消してはいけない。
      HiveService.debugSetStartupState(
        reset: const {accounts},
        volatile: const {drafts},
      );

      HiveService.consumeStartupIssue();

      expect(HiveService.resetBoxNames, contains(accounts));
      expect(HiveService.volatileBoxNames, contains(drafts));
      expect(HiveService.isVolatile(drafts), isTrue);
    });
  });

  group('isVolatile', () {
    test('メモリ上のみのボックスだけ true', () {
      HiveService.debugSetStartupState(
        reset: const {accounts},
        volatile: const {drafts},
      );

      expect(HiveService.isVolatile(drafts), isTrue);
      // 破棄して作り直した場合は永続化される。volatile ではない。
      expect(HiveService.isVolatile(accounts), isFalse);
    });

    test('問題が無ければ false', () {
      HiveService.debugSetStartupState();

      expect(HiveService.isVolatile(drafts), isFalse);
      expect(HiveService.isVolatile(accounts), isFalse);
    });
  });

  group('shouldDiscardOnFailure', () {
    test('ファイルI/O・ロック失敗では破棄しない', () {
      // Hive は初期化時に .lock ファイルを開いてロックする。ストレージが
      // 一時的に読めない、権限が無い、といった復旧可能なケースなので
      // トークンを消してはいけない。
      final lockFailure = FileSystemException(
        'lock failed',
        '/data/user/0/app/hive/accounts.lock',
        const OSError('Resource temporarily unavailable', 11),
      );

      expect(HiveService.shouldDiscardOnFailure(lockFailure), isFalse);
    });

    test('ファイルが開けない場合も破棄しない', () {
      expect(
        HiveService.shouldDiscardOnFailure(
          const PathNotFoundException('/data/user/0/app/hive', OSError()),
        ),
        isFalse,
      );
    });

    test('形式不整合（HiveError）は破棄する', () {
      expect(
        HiveService.shouldDiscardOnFailure(
          HiveError('Cannot read, unknown typeId: 3'),
        ),
        isTrue,
      );
    });

    test('アダプターの読み取り超過（RangeError）は破棄する', () {
      expect(
        HiveService.shouldDiscardOnFailure(RangeError('offset')),
        isTrue,
      );
    });

    test('未知の例外は破棄側に倒す', () {
      // 形式不整合を取りこぼすと step 2 が永久に動かず、メモリ上で
      // 動き続けて復旧手段が無くなるため。
      expect(
        HiveService.shouldDiscardOnFailure(StateError('unexpected')),
        isTrue,
      );
    });

    test('保存先ディレクトリが取れていない場合は何であれ破棄しない', () {
      // ファイルに一切触れていないので、破棄する対象も無くデータは無傷。
      HiveService.debugSetStartupState(storageDirectoryAvailable: false);

      expect(
        HiveService.shouldDiscardOnFailure(
          HiveError('You need to initialize Hive or provide a path'),
        ),
        isFalse,
      );
      expect(
        HiveService.shouldDiscardOnFailure(StateError('unexpected')),
        isFalse,
      );
    });
  });

  group('公開している集合は変更できない', () {
    test('resetBoxNames / volatileBoxNames は変更不可', () {
      HiveService.debugSetStartupState(
        reset: const {accounts},
        volatile: const {drafts},
      );

      expect(
        () => HiveService.resetBoxNames.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => HiveService.volatileBoxNames.add('x'),
        throwsUnsupportedError,
      );
    });
  });
}
