import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:coerie/core/constants/app_constants.dart';
import 'package:coerie/data/local/hive_service.dart';
import 'package:coerie/data/models/account_model.dart';

/// 「開発者がフィールドを並べ替えた」アダプター。既存レコードの読み取りが
/// `RangeError` で落ちる状況を再現する（step 1 を失敗させる）。
class _ReorderedAccountAdapter extends TypeAdapter<AccountModel> {
  @override
  final int typeId = 1;

  @override
  AccountModel read(BinaryReader reader) {
    // 先頭にフィールドを1つ増やしてしまった場合。既存レコードには
    // その分のバイトが無いので readString が最後に足りなくなる。
    for (var i = 0; i < 7; i++) {
      reader.readString();
    }
    throw StateError('ここには到達しない');
  }

  @override
  void write(BinaryWriter writer, AccountModel obj) =>
      throw UnimplementedError();
}

AccountModel _account(String id) => AccountModel(
      id: id,
      host: 'misskey.kasu.me',
      token: 'token-$id',
      userId: 'user-$id',
      username: 'name$id',
      name: '表示名$id',
      isActive: false,
    );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('coerie_hive_test');
    HiveService.debugSetStartupState();
  });

  tearDown(() async {
    await Hive.close();
    HiveService.debugSetStartupState();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows では開いていたファイルのハンドルが残り削除できないことがある。
      // 一時ディレクトリなので放置してよい。
    }
  });

  /// 正常な accounts ボックスを作って閉じ、ファイルの中身を返す。
  Future<File> seedAccounts(int count) async {
    Hive.init(dir.path);
    Hive.registerAdapter(AccountModelAdapter(), override: true);
    final box = await Hive.openBox<AccountModel>(AppConstants.accountsBox);
    for (var i = 0; i < count; i++) {
      await box.put('a$i', _account('a$i'));
    }
    await box.close();
    return File('${dir.path}${Platform.pathSeparator}accounts.hive');
  }

  group('自動復旧によるレコード欠落の検知', () {
    test('中間が壊れていると accountsPartiallyLost として通知される', () async {
      final file = await seedAccounts(3);
      final sizeBefore = file.lengthSync();

      // 中間の1バイトを反転させて CRC を壊す。crashRecovery が
      // 「読めなくなった位置以降」を切り捨てるので、後続の正常なレコードまで消える。
      final bytes = file.readAsBytesSync();
      final pos = bytes.length ~/ 2;
      bytes[pos] = bytes[pos] ^ 0xFF;
      file.writeAsBytesSync(bytes);

      await HiveService.debugInitAt(dir.path);

      expect(
        file.lengthSync(),
        lessThan(sizeBefore),
        reason: 'crashRecovery が truncate しているはず',
      );
      expect(
        HiveService.recoveredBoxNames,
        contains(AppConstants.accountsBox),
      );
      expect(
        HiveService.consumeStartupIssue(),
        HiveStartupIssue.accountsPartiallyLost,
      );
      // 破棄も非永続化もしていない（step 1 は成功している）。
      expect(HiveService.resetBoxNames, isEmpty);
      expect(HiveService.volatileBoxNames, isEmpty);
      expect(HiveService.isVolatile(AppConstants.accountsBox), isFalse);
    });

    test('健全なボックスでは何も通知されない', () async {
      final file = await seedAccounts(3);
      final sizeBefore = file.lengthSync();

      await HiveService.debugInitAt(dir.path);

      // 正常なオープンは1バイトも縮めない。ここが崩れると毎起動で誤警告が出る。
      expect(file.lengthSync(), sizeBefore);
      expect(HiveService.recoveredBoxNames, isEmpty);
      expect(HiveService.consumeStartupIssue(), isNull);
      expect(HiveService.accountsBox.length, 3);
    });

    test('ボックスが無い初回起動でも誤検知しない', () async {
      await HiveService.debugInitAt(dir.path);

      expect(HiveService.recoveredBoxNames, isEmpty);
      expect(HiveService.consumeStartupIssue(), isNull);
    });
  });

  group('アダプターの形式不整合からの復旧', () {
    test('読めないアダプターでも起動でき、理由が記録される', () async {
      await seedAccounts(2);
      // step 1 を失敗させる。debugInitAt は登録済みアダプターを上書きしない。
      Hive.registerAdapter(_ReorderedAccountAdapter(), override: true);

      await HiveService.debugInitAt(dir.path);

      // 何段目に落ちたかは環境による（Windows では開いていたファイルを消せず
      // step 2 が失敗して step 3 になる）。共通して言えるのは次の2点。
      expect(
        Hive.isBoxOpen(AppConstants.accountsBox),
        isTrue,
        reason: 'どの段に落ちてもボックスは開いた状態で返ること',
      );
      expect(
        HiveService.consumeStartupIssue(),
        isNotNull,
        reason: 'ユーザーに理由を提示できること',
      );
      // 中身が読めなかった以上、アカウントは残っていない。
      expect(HiveService.accountsBox.isEmpty, isTrue);
    });

    test('オープン失敗時に未処理の非同期エラーを zone に漏らさない', () async {
      // hive の HiveImpl._openBox は、誰も listen していない内部 completer にも
      // エラーを流してから rethrow する。握り漏らすとこのテスト自身が無関係な
      // RangeError で落ちる（_openBoxIsolated が無い状態では実際に落ちた）。
      await seedAccounts(2);
      Hive.registerAdapter(_ReorderedAccountAdapter(), override: true);

      await HiveService.debugInitAt(dir.path);
      // 漏れたエラーはマイクロタスク経由で届くので、少し待ってから抜ける。
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(Hive.isBoxOpen(AppConstants.accountsBox), isTrue);
    });
  });
}
