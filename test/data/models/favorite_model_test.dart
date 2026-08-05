import 'package:coerie/data/models/note_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `i/favorites` のラッパーを取り違えていないことを確かめる。
///
/// 以前は API 層がラッパーを剥がして中の Note だけ返しており、画面側が
/// ノートのIDを untilId に渡していた。お気に入りレコードのIDとノートのIDは
/// どちらも同じ aid 形式のためサーバーはエラーを返さず、投稿日時を基準に
/// 切った別の窓が返って 2ページ目以降で重複・欠落が静かに起きていた。
void main() {
  Map<String, dynamic> favoriteJson({
    required String favoriteId,
    required String noteId,
  }) => {
    'id': favoriteId,
    'createdAt': '2026-08-01T12:00:00.000Z',
    'note': {
      'id': noteId,
      'createdAt': '2026-07-01T09:00:00.000Z',
      'text': 'ほんぶん',
      'user': {'id': 'user1', 'username': 'alice', 'name': 'Alice'},
    },
  };

  group('FavoriteModel', () {
    test('ノートのIDではなくお気に入りレコードのIDを保持する', () {
      final favorite = FavoriteModel.fromJson(
        favoriteJson(favoriteId: 'fav-1', noteId: 'note-1'),
        host: 'example.com',
      );

      expect(favorite.id, 'fav-1');
      expect(favorite.note.id, 'note-1');
      // カーソルに使うのはこちら。取り違えるとページングが壊れる。
      expect(favorite.id, isNot(favorite.note.id));
    });

    test('入れ子のノートを解釈する', () {
      final favorite = FavoriteModel.fromJson(
        favoriteJson(favoriteId: 'fav-2', noteId: 'note-2'),
        host: 'example.com',
      );

      expect(favorite.note.text, 'ほんぶん');
      expect(favorite.note.user.username, 'alice');
      expect(
        favorite.note.createdAt,
        DateTime.parse('2026-07-01T09:00:00.000Z'),
      );
    });

    test('一覧の末尾がページングのカーソルになる（新しい順に返るため）', () {
      final favorites = [
        favoriteJson(favoriteId: 'fav-3', noteId: 'note-3'),
        favoriteJson(favoriteId: 'fav-2', noteId: 'note-2'),
        favoriteJson(favoriteId: 'fav-1', noteId: 'note-1'),
      ].map((e) => FavoriteModel.fromJson(e, host: 'example.com')).toList();

      expect(favorites.last.id, 'fav-1');
    });
  });
}
