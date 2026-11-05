import 'package:coerie/data/models/custom_emoji_model.dart';
import 'package:coerie/features/compose/emoji_picker_sheet.dart';
import 'package:coerie/shared/providers/custom_emoji_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customEmojisProvider.overrideWith(
            (ref) async => const [
              CustomEmojiModel(
                name: 'blobcat',
                url: 'https://example.com/blobcat.png',
                aliases: ['ねこ'],
              ),
              CustomEmojiModel(name: 'no_url'),
            ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const EmojiPickerSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder emojiCell(String name) => find.descendant(
    of: find.byWidgetPredicate((w) => w is Tooltip && w.message == ':$name:'),
    matching: find.byType(InkWell),
  );

  testWidgets('ピッカーの絵文字を長押しすると、ピッカーを閉じずに詳細が開く', (tester) async {
    await openPicker(tester);

    await tester.longPress(emojiCell('blobcat'));
    await tester.pumpAndSettle();

    expect(find.text('blobcat'), findsOneWidget);
    expect(find.text('ねこ'), findsOneWidget);
    expect(find.byType(EmojiPickerSheet), findsOneWidget);
  });

  testWidgets('URLのない絵文字は長押ししても詳細が開かない', (tester) async {
    await openPicker(tester);

    await tester.longPress(emojiCell('no_url'));
    await tester.pumpAndSettle();

    expect(find.text('名前'), findsNothing);
  });

  testWidgets('ピッカー上でコピーした通知は、Scaffold の外に出て1秒後に消える', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openPicker(tester);
    await tester.longPress(emojiCell('blobcat'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, ':blobcat:');
    final notice = find.text('絵文字名をコピーしました');
    expect(notice, findsOneWidget);
    // Scaffold 配下に出ると、開いたままのピッカーの裏に隠れてしまう
    expect(
      find.ancestor(of: notice, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(find.byType(EmojiPickerSheet), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(notice, findsNothing);
  });
}
