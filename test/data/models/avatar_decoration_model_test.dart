import 'package:coerie/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _user({Object? decorations, bool omit = false}) => {
  'id': 'u1',
  'name': 'name',
  'username': 'user',
  'host': null,
  'avatarUrl': 'https://example.com/a.png',
  if (!omit) 'avatarDecorations': decorations,
};

void main() {
  test('省略可能な項目は既定値で補う', () {
    final user = UserModel.fromJson(
      _user(
        decorations: [
          {'id': 'd1', 'url': 'https://example.com/d1.png'},
          {
            'id': 'd2',
            'url': 'https://example.com/d2.png',
            'angle': 0.25,
            'flipH': true,
            'offsetX': -0.1,
            'offsetY': 1,
          },
        ],
      ),
    );

    final d1 = user.avatarDecorations[0];
    expect(d1.angle, 0);
    expect(d1.flipH, false);
    expect(d1.offsetX, 0);
    expect(d1.offsetY, 0);

    final d2 = user.avatarDecorations[1];
    expect(d2.angle, 0.25);
    expect(d2.flipH, true);
    expect(d2.offsetX, -0.1);
    expect(d2.offsetY, 1.0);
  });

  test('フィールドを返さないサーバーでは空になる', () {
    expect(UserModel.fromJson(_user(omit: true)).avatarDecorations, isEmpty);
    expect(UserModel.fromJson(_user()).avatarDecorations, isEmpty);
  });

  test('url の無い不正な要素は捨てる', () {
    final user = UserModel.fromJson(
      _user(
        decorations: [
          {'id': 'd1'},
          {'id': 'd2', 'url': 'https://example.com/d2.png'},
        ],
      ),
    );
    expect(user.avatarDecorations.map((d) => d.id), ['d2']);
  });
}
