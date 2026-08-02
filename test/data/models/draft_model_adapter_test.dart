import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// BinaryReader/BinaryWriter の実装クラスは公開APIに含まれないため、
// アダプターのバイナリ互換性を検証する目的に限り実装を直接インポートする。
// ignore: implementation_imports
import 'package:hive/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_writer_impl.dart';

import 'package:coerie/data/models/draft_model.dart';
import 'package:coerie/data/models/note_model.dart';

/// 過去に実際に書き込まれた形式のバイト列を再現する。
///
/// `DraftModelAdapter` は末尾追加でフィールドを増やしてきたため、端末には
/// 追加時期の異なる4世代のレコードが混在しうる。フラグを落とすことで
/// それぞれの世代を再現する。
///
/// **このヘルパーは絶対に変更しないこと。** 現行 write() の写しではなく、
/// 「過去に書き込まれたデータ」のスナップショットとして機能する。
Uint8List writeLegacyFormat(
  DraftModel obj, {
  bool withFiles = true,
  bool withCw = true,
  bool withIsSensitive = true,
}) {
  final writer = BinaryWriterImpl(Hive);

  // 第1世代: ここまでは全レコードに必ず存在する。
  writer.writeString(obj.id);
  writer.writeString(obj.text);
  writer.writeString(obj.visibility);
  writer.writeInt(obj.savedAt.millisecondsSinceEpoch);

  // 第2世代: files を追加。
  if (!withFiles) return writer.toBytes();
  writer.writeStringList(
    obj.files.map((f) => jsonEncode(f.toJson())).toList(),
  );

  // 第3世代: cw を追加（null は空文字として保存される）。
  if (!withCw) return writer.toBytes();
  writer.writeString(obj.cw ?? '');

  // 第4世代（v0.9.1 時点の現行形式）: isSensitive を追加。
  if (!withIsSensitive) return writer.toBytes();
  writer.writeInt(obj.isSensitive ? 1 : 0);

  return writer.toBytes();
}

DraftModel readWithCurrentAdapter(Uint8List bytes) =>
    DraftModelAdapter().read(BinaryReaderImpl(bytes, Hive));

void main() {
  final savedAt = DateTime.fromMillisecondsSinceEpoch(1754092800000);

  const file = DriveFileModel(
    id: '9zx1',
    name: 'photo.png',
    type: 'image/png',
    url: 'https://misskey.kasu.me/files/photo.png',
    thumbnailUrl: 'https://misskey.kasu.me/thumb/photo.png',
    size: 12345,
    isSensitive: true,
  );

  final sample = DraftModel(
    id: 'b1c2d3e4-0000-4444-8888-99aabbccddee',
    text: 'テスト投稿の下書き',
    visibility: 'home',
    savedAt: savedAt,
    files: const [file],
    cw: '注意書き',
    isSensitive: true,
  );

  void expectSampleCore(DraftModel decoded) {
    expect(decoded.id, sample.id);
    expect(decoded.text, sample.text);
    expect(decoded.visibility, sample.visibility);
    expect(decoded.savedAt, sample.savedAt);
  }

  group('DraftModelAdapter のバイナリ互換性', () {
    test('v0.9.1 形式のレコードを現行アダプターで読める', () {
      final decoded = readWithCurrentAdapter(writeLegacyFormat(sample));

      expectSampleCore(decoded);
      expect(decoded.files, hasLength(1));
      expect(decoded.files.first.id, file.id);
      expect(decoded.files.first.name, file.name);
      expect(decoded.files.first.url, file.url);
      expect(decoded.files.first.thumbnailUrl, file.thumbnailUrl);
      expect(decoded.files.first.size, file.size);
      expect(decoded.files.first.isSensitive, isTrue);
      expect(decoded.cw, sample.cw);
      expect(decoded.isSensitive, isTrue);
    });

    test('第1世代（id/text/visibility/savedAt のみ）のレコードを読める', () {
      final decoded = readWithCurrentAdapter(
        writeLegacyFormat(sample, withFiles: false),
      );

      expectSampleCore(decoded);
      expect(decoded.files, isEmpty);
      expect(decoded.cw, isNull);
      expect(decoded.isSensitive, isFalse);
    });

    test('第2世代（files まで）のレコードを読める', () {
      final decoded = readWithCurrentAdapter(
        writeLegacyFormat(sample, withCw: false),
      );

      expectSampleCore(decoded);
      expect(decoded.files, hasLength(1));
      expect(decoded.cw, isNull);
      expect(decoded.isSensitive, isFalse);
    });

    test('第3世代（cw まで）のレコードを読める', () {
      final decoded = readWithCurrentAdapter(
        writeLegacyFormat(sample, withIsSensitive: false),
      );

      expectSampleCore(decoded);
      expect(decoded.cw, sample.cw);
      expect(decoded.isSensitive, isFalse);
    });

    test('空文字で保存された cw は null として読まれる', () {
      final noCw = DraftModel(
        id: sample.id,
        text: sample.text,
        visibility: sample.visibility,
        savedAt: savedAt,
        files: const [],
        isSensitive: false,
      );

      final decoded = readWithCurrentAdapter(writeLegacyFormat(noCw));

      expect(decoded.cw, isNull);
      expect(decoded.files, isEmpty);
      expect(decoded.isSensitive, isFalse);
    });

    test('現行アダプターの書き出しは v0.9.1 形式を接頭辞として保持する', () {
      final writer = BinaryWriterImpl(Hive);
      DraftModelAdapter().write(writer, sample);
      final current = writer.toBytes();
      final legacy = writeLegacyFormat(sample);

      // 末尾へのフィールド追加は許容し（バイト列が伸びるだけ）、
      // 削除・並べ替え・型変更だけを検出する。
      // ここが落ちたら、既存ユーザーの端末にある下書きを読めなくする変更を
      // 加えたということ。フィールドは必ず末尾にのみ追加すること。
      expect(current.length, greaterThanOrEqualTo(legacy.length));
      expect(
        current.sublist(0, legacy.length),
        equals(legacy),
        reason: '既存フィールドのバイト表現が変わっている（末尾追加以外の変更）',
      );
    });

    test('壊れた添付ファイルJSONはその要素だけ捨てて読み進める', () {
      // files は JSON 文字列のリストとして保存されるため、DriveFileModel の
      // 仕様変更で個々の要素が読めなくなることがある。レコード全体を
      // 巻き添えにしない（= 下書きごと失わない）ことを固定する。
      final writer = BinaryWriterImpl(Hive);
      writer.writeString(sample.id);
      writer.writeString(sample.text);
      writer.writeString(sample.visibility);
      writer.writeInt(sample.savedAt.millisecondsSinceEpoch);
      writer.writeStringList([
        'これはJSONではない',
        jsonEncode(file.toJson()),
        '{"id":"必須フィールドが欠けている"}',
      ]);
      writer.writeString(sample.cw ?? '');
      writer.writeInt(sample.isSensitive ? 1 : 0);

      final decoded = readWithCurrentAdapter(writer.toBytes());

      expectSampleCore(decoded);
      expect(decoded.files, hasLength(1));
      expect(decoded.files.first.id, file.id);
      expect(decoded.cw, sample.cw);
      expect(decoded.isSensitive, isTrue);
    });

    test('現行アダプター同士の往復で値が保たれる', () {
      final writer = BinaryWriterImpl(Hive);
      DraftModelAdapter().write(writer, sample);

      final decoded = readWithCurrentAdapter(writer.toBytes());

      expectSampleCore(decoded);
      expect(decoded.files.map((f) => f.toJson()), [file.toJson()]);
      expect(decoded.cw, sample.cw);
      expect(decoded.isSensitive, sample.isSensitive);
    });
  });
}
