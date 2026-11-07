import 'dart:async';

import 'package:coerie/core/streaming/streaming_service.dart';
import 'package:coerie/data/models/account_model.dart';
import 'package:coerie/data/models/custom_emoji_model.dart';
import 'package:coerie/data/models/note_model.dart';
import 'package:coerie/data/models/user_model.dart';
import 'package:coerie/data/remote/misskey_api.dart';
import 'package:coerie/features/timeline/timeline_provider.dart';
import 'package:coerie/features/timeline/timeline_screen.dart';
import 'package:coerie/shared/providers/account_provider.dart';
import 'package:coerie/shared/providers/custom_emoji_provider.dart';
import 'package:coerie/shared/providers/misskey_api_provider.dart';
import 'package:coerie/shared/providers/shared_preferences_provider.dart';
import 'package:coerie/shared/providers/word_mute_provider.dart';
import 'package:coerie/shared/utils/word_mute.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _timelineType = 'home';

NoteModel _note(String id) => NoteModel(
  id: id,
  createdAt: DateTime(2026),
  user: const UserModel(
    id: 'author',
    name: 'author',
    username: 'author',
    host: '',
  ),
  text: 'note-$id',
  visibility: 'public',
);

class _FakeApi extends MisskeyApi {
  _FakeApi(this.notes) : super(host: 'example.com', token: 't');

  final List<NoteModel> notes;
  final List<(String, String)> created = [];

  /// 指定すると createReaction はこの完了まで応答しない。
  Completer<void>? createGate;
  Object? createError;

  @override
  Future<List<NoteModel>> getTimeline({
    required String endpoint,
    int limit = 20,
    String? untilId,
    String? sinceId,
    Map<String, dynamic> extraParams = const {},
  }) async => notes;

  @override
  Future<void> createReaction(String noteId, String reaction) async {
    created.add((noteId, reaction));
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
  }
}

/// サーバーへ接続せず、ノート更新イベントだけをテストから流す。
class _FakeStreaming extends StreamingService {
  _FakeStreaming() : super(host: 'example.com', token: 't');

  final StreamController<NoteUpdateEvent> updates =
      StreamController<NoteUpdateEvent>.broadcast();

  @override
  Stream<NoteUpdateEvent> get noteUpdateStream => updates.stream;

  void echoMyReaction(String noteId) => updates.add(
    NoteUpdateEvent(
      noteId: noteId,
      type: 'reacted',
      reaction: ':blobcat@.:',
      userId: 'me',
    ),
  );
}

void main() {
  late _FakeApi api;
  late ProviderContainer container;

  Future<void> pumpTimeline(
    WidgetTester tester, {
    StreamingService? streaming,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = _FakeApi([_note('a')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeAccountProvider.overrideWithValue(
            AccountModel(
              id: 'account',
              host: 'example.com',
              token: 't',
              userId: 'me',
              username: 'me',
              name: 'me',
              isActive: true,
            ),
          ),
          misskeyApiProvider.overrideWithValue(api),
          streamingServiceProvider.overrideWithValue(streaming),
          wordMuteFilterProvider.overrideWithValue(WordMuteFilter.empty),
          customEmojisProvider.overrideWith(
            (ref) async => const [
              CustomEmojiModel(
                name: 'blobcat',
                url: 'https://example.com/blobcat.png',
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TimelineScreen(timelineType: _timelineType)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(TimelineScreen)),
    );
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add_reaction_outlined).first);
    await tester.pumpAndSettle();
  }

  Future<void> pickBlobcat(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == ':blobcat:',
        ),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
  }

  void prepend(String id) => container
      .read(timelineProvider(_timelineType).notifier)
      .prependNote(_note(id));

  NoteModel noteInTimeline(String id) => container
      .read(timelineProvider(_timelineType))
      .notes
      .firstWhere((n) => n.id == id);

  testWidgets('ピッカーを開いている間にタイムラインが更新されてもリアクションが付く', (tester) async {
    await pumpTimeline(tester);
    await openPicker(tester);

    prepend('b');
    await tester.pumpAndSettle();

    await pickBlobcat(tester);

    expect(api.created, [('a', ':blobcat:')]);
    expect(noteInTimeline('a').myReaction, ':blobcat@.:');
    expect(noteInTimeline('a').reactions, {':blobcat@.:': 1});
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('APIの応答待ちの間にタイムラインが更新されてもリアクションが表示される', (tester) async {
    await pumpTimeline(tester);
    api.createGate = Completer<void>();
    await openPicker(tester);
    await pickBlobcat(tester);

    prepend('b');
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);

    api.createGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('付けたリアクションは次のタイムライン更新で消えない', (tester) async {
    await pumpTimeline(tester);
    await openPicker(tester);
    await pickBlobcat(tester);
    expect(find.text('1'), findsOneWidget);

    prepend('b');
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('リノートの中身へのリアクションもタイムライン更新で消えない', (tester) async {
    await pumpTimeline(tester);
    container
        .read(timelineProvider(_timelineType).notifier)
        .prependNote(
          NoteModel(
            id: 'wrapper',
            createdAt: DateTime(2026),
            user: _note('x').user,
            visibility: 'public',
            renote: _note('inner'),
          ),
        );
    await tester.pumpAndSettle();
    await openPicker(tester);
    await pickBlobcat(tester);

    prepend('b');
    await tester.pumpAndSettle();

    expect(api.created, [('inner', ':blobcat:')]);
    expect(noteInTimeline('wrapper').renote!.myReaction, ':blobcat@.:');
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('カード破棄後に送信が失敗したらエラーを通知する', (tester) async {
    await pumpTimeline(tester);
    api.createError = Exception('failed');
    await openPicker(tester);

    prepend('b');
    await tester.pumpAndSettle();
    await pickBlobcat(tester);

    expect(api.created, [('a', ':blobcat:')]);
    expect(find.text('リアクションに失敗しました'), findsOneWidget);
    expect(noteInTimeline('a').myReaction, isNull);
  });

  group('作り直されたカードに届く自分のエコー', () {
    testWidgets('API応答の後に届いても二重に数えない', (tester) async {
      final streaming = _FakeStreaming();
      await pumpTimeline(tester, streaming: streaming);
      await openPicker(tester);

      prepend('b');
      await tester.pumpAndSettle();
      await pickBlobcat(tester);

      streaming.echoMyReaction('a');
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('API応答より先に届いても二重に数えない', (tester) async {
      final streaming = _FakeStreaming();
      await pumpTimeline(tester, streaming: streaming);
      api.createGate = Completer<void>();
      await openPicker(tester);

      prepend('b');
      await tester.pumpAndSettle();
      await pickBlobcat(tester);

      streaming.echoMyReaction('a');
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      api.createGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('同一アカウントの別端末からの操作は反映する', (tester) async {
      final streaming = _FakeStreaming();
      await pumpTimeline(tester, streaming: streaming);

      streaming.echoMyReaction('a');
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
