import 'package:coerie/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `users/following` / `users/followers` のラッパーを取り違えていないことを確かめる。
///
/// 以前は API 層がラッパーを剥がして中の User だけ返しており、
/// ページングのカーソルにユーザーIDを渡していた。フォロー関係レコードのIDと
/// ユーザーのIDはどちらも同じ aid 形式のためサーバーはエラーを返さず、
/// アカウント作成日時を基準に切った別の窓が返って
/// 2ページ目以降で重複・欠落が静かに起きていた。
void main() {
  Map<String, dynamic> relationJson({
    required String relationId,
    required String userId,
    required String userKey,
  }) => {
    'id': relationId,
    'createdAt': '2026-08-01T12:00:00.000Z',
    userKey: {'id': userId, 'username': 'alice', 'name': 'Alice'},
  };

  group('FollowingModel', () {
    test('users/following ではユーザーIDではなくフォロー関係レコードのIDを保持する', () {
      final item = FollowingModel.fromJson(
        relationJson(
          relationId: 'following-1',
          userId: 'user-1',
          userKey: 'followee',
        ),
        userKey: 'followee',
        host: 'example.com',
      );

      expect(item.id, 'following-1');
      expect(item.user.id, 'user-1');
      // カーソルに使うのはこちら。取り違えるとページングが壊れる。
      expect(item.id, isNot(item.user.id));
    });

    test('users/followers では follower を取り出す', () {
      final item = FollowingModel.fromJson(
        relationJson(
          relationId: 'following-2',
          userId: 'user-2',
          userKey: 'follower',
        ),
        userKey: 'follower',
        host: 'example.com',
      );

      expect(item.id, 'following-2');
      expect(item.user.id, 'user-2');
      expect(item.user.username, 'alice');
    });

    test('copyWith はユーザーだけ差し替えてレコードIDを保つ', () {
      final item = FollowingModel.fromJson(
        relationJson(
          relationId: 'following-3',
          userId: 'user-3',
          userKey: 'followee',
        ),
        userKey: 'followee',
        host: 'example.com',
      );

      // リレーション情報の反映（users/relation）で通る経路。
      final updated = item.copyWith(
        user: item.user.copyWith(isFollowing: true),
      );

      expect(updated.id, 'following-3');
      expect(updated.user.id, 'user-3');
      expect(updated.user.isFollowing, isTrue);
      expect(item.user.isFollowing, isFalse, reason: '元のインスタンスは変更しない');
    });
  });
}
