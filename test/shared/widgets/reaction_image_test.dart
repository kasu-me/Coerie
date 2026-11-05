import 'package:coerie/shared/widgets/reaction_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('読み込み中は親の幅に広がらず正方形の枠に収まる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: Row(
                children: [
                  // リアクションチップと同じく、幅の上限だけが渡る配置
                  Flexible(
                    child: ReactionImage(
                      imageUrl: 'https://example.com/emoji.png',
                      size: 18,
                      fallback: Text('emoji'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ReactionImage)), const Size(18, 18));
  });
}
