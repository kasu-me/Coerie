import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// BinaryReader/BinaryWriter の実装クラスは公開APIに含まれないため、
// アダプターのバイナリ互換性を検証する目的に限り実装を直接インポートする。
// ignore: implementation_imports
import 'package:hive/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_writer_impl.dart';

import 'package:coerie/data/models/account_model.dart';

/// v0.9.1 時点（`availableBytes` ガード導入前）の [AccountModelAdapter.write] と
/// 同じバイト列を書き出す。既存ユーザーの端末に保存されている形式。
///
/// **このヘルパーは絶対に変更しないこと。** 現行の write() の写しではなく、
/// 「過去に書き込まれたデータ」のスナップショットとして機能する。
Uint8List writeV0_9_1Format(AccountModel obj) {
  final writer = BinaryWriterImpl(Hive);
  writer.writeString(obj.id);
  writer.writeString(obj.host);
  writer.writeString(obj.token);
  writer.writeString(obj.userId);
  writer.writeString(obj.username);
  writer.writeString(obj.name);
  final hasAvatar = obj.avatarUrl != null;
  writer.writeBool(hasAvatar);
  if (hasAvatar) writer.writeString(obj.avatarUrl!);
  writer.writeBool(obj.isActive);
  return writer.toBytes();
}

/// `name` までしか書かれていない、末尾フィールドを欠いたレコード。
/// 将来フィールドを追加したあと、追加前のデータを読む状況を模している。
Uint8List writeTruncatedFormat(AccountModel obj) {
  final writer = BinaryWriterImpl(Hive);
  writer.writeString(obj.id);
  writer.writeString(obj.host);
  writer.writeString(obj.token);
  writer.writeString(obj.userId);
  writer.writeString(obj.username);
  writer.writeString(obj.name);
  return writer.toBytes();
}

AccountModel readWithCurrentAdapter(Uint8List bytes) =>
    AccountModelAdapter().read(BinaryReaderImpl(bytes, Hive));

void main() {
  final sample = AccountModel(
    id: '5a3f1c9e-2b7d-4e18-9f60-1c2d3e4f5a6b',
    host: 'misskey.kasu.me',
    token: 'dummy-token',
    userId: '9abc123',
    username: 'cupmen',
    name: 'かすみ',
    avatarUrl: 'https://misskey.kasu.me/avatar.png',
    isActive: true,
  );

  group('AccountModelAdapter のバイナリ互換性', () {
    test('v0.9.1 形式のレコードを現行アダプターで読める', () {
      final decoded = readWithCurrentAdapter(writeV0_9_1Format(sample));

      expect(decoded.id, sample.id);
      expect(decoded.host, sample.host);
      expect(decoded.token, sample.token);
      expect(decoded.userId, sample.userId);
      expect(decoded.username, sample.username);
      expect(decoded.name, sample.name);
      expect(decoded.avatarUrl, sample.avatarUrl);
      expect(decoded.isActive, isTrue);
    });

    test('avatarUrl が null の v0.9.1 形式も読める', () {
      final noAvatar = AccountModel(
        id: sample.id,
        host: sample.host,
        token: sample.token,
        userId: sample.userId,
        username: sample.username,
        name: sample.name,
        isActive: false,
      );

      final decoded = readWithCurrentAdapter(writeV0_9_1Format(noAvatar));

      expect(decoded.avatarUrl, isNull);
      expect(decoded.isActive, isFalse);
    });

    test('現行アダプターの書き出しは v0.9.1 形式を接頭辞として保持する', () {
      final writer = BinaryWriterImpl(Hive);
      AccountModelAdapter().write(writer, sample);
      final current = writer.toBytes();
      final legacy = writeV0_9_1Format(sample);

      // 末尾へのフィールド追加は許容し（バイト列が伸びるだけ）、
      // 削除・並べ替え・型変更だけを検出する。
      // ここが落ちたら、既存ユーザーの端末にあるデータを読めなくする変更を
      // 加えたということ。フィールドは必ず末尾にのみ追加すること。
      expect(current.length, greaterThanOrEqualTo(legacy.length));
      expect(
        current.sublist(0, legacy.length),
        equals(legacy),
        reason: '既存フィールドのバイト表現が変わっている（末尾追加以外の変更）',
      );
    });

    test('末尾フィールドを欠いたレコードは既定値で読める', () {
      final decoded = readWithCurrentAdapter(writeTruncatedFormat(sample));

      expect(decoded.name, sample.name);
      expect(decoded.avatarUrl, isNull);
      expect(decoded.isActive, isFalse);
    });

    test('現行アダプター同士の往復で値が保たれる', () {
      final writer = BinaryWriterImpl(Hive);
      AccountModelAdapter().write(writer, sample);

      final decoded = readWithCurrentAdapter(writer.toBytes());

      expect(decoded.toJson(), equals(sample.toJson()));
    });
  });
}
