import 'package:coerie/core/constants/app_constants.dart';
import 'package:coerie/data/models/note_model.dart';
import 'package:coerie/shared/utils/visibility_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 公開範囲まわりの共通化した判定を確かめる。
///
/// アイコンの switch は note_card（通常・リノート）・compose・draft の4箇所に、
/// リノート可否の判定は note_card の2箇所に散っていた。公開範囲を増やしたときに
/// 直し漏れが出ないよう、1箇所に寄せたうえで固定する。
void main() {
  NoteModel note({required String visibility, String authorId = 'author'}) =>
      NoteModel.fromJson({
        'id': 'note-1',
        'createdAt': '2026-08-01T00:00:00.000Z',
        'visibility': visibility,
        'user': {'id': authorId, 'username': 'alice', 'name': 'Alice'},
      });

  group('visibilityIcon', () {
    test('公開範囲ごとに対応するアイコンを返す', () {
      expect(visibilityIcon(AppConstants.visibilityPublic), Icons.public);
      expect(visibilityIcon(AppConstants.visibilityHome), Icons.home_outlined);
      expect(
        visibilityIcon(AppConstants.visibilityFollowers),
        Icons.lock_outline,
      );
      expect(
        visibilityIcon(AppConstants.visibilitySpecified),
        Icons.mail_outline,
      );
    });

    test('未知の公開範囲は全体公開に倒す', () {
      expect(visibilityIcon('unknown-visibility'), Icons.public);
    });

    test('すべてのラベルに対応するアイコンがある', () {
      for (final visibility in AppConstants.visibilityLabels.keys) {
        expect(visibilityIcon(visibility), isNotNull);
      }
    });
  });

  group('NoteModel.canRenoteBy', () {
    test('全体公開・ホームは誰でもリノートできる', () {
      expect(
        note(visibility: AppConstants.visibilityPublic).canRenoteBy('viewer'),
        isTrue,
      );
      expect(
        note(visibility: AppConstants.visibilityHome).canRenoteBy('viewer'),
        isTrue,
      );
    });

    test('フォロワー限定は投稿者本人だけリノートできる', () {
      final n = note(
        visibility: AppConstants.visibilityFollowers,
        authorId: 'author',
      );
      expect(n.canRenoteBy('author'), isTrue);
      expect(n.canRenoteBy('viewer'), isFalse);
      expect(n.canRenoteBy(null), isFalse, reason: '未ログインは本人ではない');
    });

    test('ダイレクトは投稿者本人でもリノートできない', () {
      final n = note(
        visibility: AppConstants.visibilitySpecified,
        authorId: 'author',
      );
      expect(n.canRenoteBy('author'), isFalse);
      expect(n.canRenoteBy('viewer'), isFalse);
    });
  });
}
