import 'package:coerie/data/models/muted_word_model.dart';
import 'package:coerie/data/models/note_model.dart';
import 'package:coerie/shared/utils/word_mute.dart';
import 'package:flutter_test/flutter_test.dart';

/// ワードミュートは Misskey サーバーがタイムラインから除外してくれないため、
/// クライアント側の判定が本家 `checkWordMute` と同じ結果になることを担保する。
void main() {
  NoteModel note({
    String id = 'note-1',
    String userId = 'other',
    String? text,
    String? cw,
    NoteModel? renote,
  }) => NoteModel.fromJson({
    'id': id,
    'createdAt': '2026-09-01T00:00:00.000Z',
    'text': text,
    'cw': cw,
    'visibility': 'public',
    'user': {'id': userId, 'username': 'alice', 'name': 'Alice'},
    if (renote != null) 'renote': _toJson(renote),
  }, host: 'example.com');

  group('MutedWordModel', () {
    test('キーワード配列は全語を含むときだけ一致する（AND条件）', () {
      final word = MutedWordModel.keywords(['猫', '写真']);
      expect(word.matches('猫の写真'), isTrue);
      expect(word.matches('猫だけ'), isFalse);
    });

    test('大文字小文字は区別する（本家と同じ）', () {
      expect(MutedWordModel.keywords(['Cat']).matches('cat'), isFalse);
      expect(MutedWordModel.keywords(['Cat']).matches('Cat'), isTrue);
    });

    test('/pattern/flags 形式は正規表現として評価される', () {
      final word = MutedWordModel.fromJson('/ね.こ/i')!;
      expect(word.isRegex, isTrue);
      expect(word.matches('ネコ'), isFalse);
      expect(word.matches('ねAこ'), isTrue);
      expect(word.matches('ねAコ'), isFalse);
    });

    test('不正な正規表現は何にも一致しない', () {
      final word = MutedWordModel.fromJson('/[/')!;
      expect(word.matches('['), isFalse);
    });

    test('正規表現エントリは文字列のまま往復する', () {
      final word = MutedWordModel.fromJson('/foo/i')!;
      expect(word.toJson(), '/foo/i');
      expect(MutedWordModel.keywords(['foo']).toJson(), ['foo']);
    });

    test('空エントリは捨てる', () {
      expect(MutedWordModel.fromJson(<String>[]), isNull);
      expect(MutedWordModel.fromJson(''), isNull);
      expect(MutedWordModel.fromJson(123), isNull);
    });
  });

  group('WordMuteSettings', () {
    test('all はソフトとハードの両方を含む', () {
      final settings = WordMuteSettings(
        soft: [
          MutedWordModel.keywords(['宣伝']),
        ],
        hard: [
          MutedWordModel.keywords(['ネタバレ']),
        ],
      );
      expect(settings.all.map((w) => w.label), ['宣伝', 'ネタバレ']);
      expect(settings.isEmpty, isFalse);
    });

    test('両方空なら isEmpty', () {
      expect(WordMuteSettings.empty.isEmpty, isTrue);
      expect(WordMuteSettings.empty.all, isEmpty);
    });

    test('ハード側だけのワードでもミュートされる', () {
      final settings = WordMuteSettings(
        hard: [
          MutedWordModel.keywords(['ネタバレ']),
        ],
      );
      final filter = WordMuteFilter(words: settings.all, viewerUserId: 'me');
      expect(filter.isMuted(note(text: 'ネタバレ注意')), isTrue);
    });
  });

  group('WordMuteFilter', () {
    final filter = WordMuteFilter(
      words: [
        MutedWordModel.keywords(['宣伝']),
      ],
      viewerUserId: 'me',
    );

    test('本文が一致するノートをミュートする', () {
      expect(filter.isMuted(note(text: 'これは宣伝です')), isTrue);
      expect(filter.isMuted(note(text: 'ふつうの投稿')), isFalse);
    });

    test('CW も判定対象に含む', () {
      expect(filter.isMuted(note(cw: '宣伝注意', text: 'ほんぶん')), isTrue);
    });

    test('自分の投稿はミュートしない', () {
      expect(filter.isMuted(note(userId: 'me', text: '宣伝')), isFalse);
    });

    test('リノート元の本文も判定する', () {
      final renoted = note(id: 'note-2', text: '宣伝です');
      expect(filter.isMuted(note(text: null, renote: renoted)), isTrue);
    });

    test('ミュート設定が空なら元のリストをそのまま返す', () {
      final notes = [note(text: '宣伝')];
      expect(WordMuteFilter.empty.apply(notes), same(notes));
    });

    test('apply は一致したノートだけを取り除く', () {
      final notes = [note(id: 'a', text: '宣伝'), note(id: 'b', text: 'ふつう')];
      expect(filter.apply(notes).map((n) => n.id), ['b']);
    });
  });
}

/// テスト用にノートを JSON へ戻す（renote の入れ子を組み立てるため）。
Map<String, dynamic> _toJson(NoteModel n) => {
  'id': n.id,
  'createdAt': n.createdAt.toIso8601String(),
  'text': n.text,
  'cw': n.cw,
  'visibility': n.visibility,
  'user': {'id': n.user.id, 'username': n.user.username, 'name': n.user.name},
};
