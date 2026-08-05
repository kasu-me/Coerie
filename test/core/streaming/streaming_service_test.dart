import 'package:coerie/core/streaming/streaming_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// タイムライン購読の参照カウントを確かめる。
///
/// 以前は [StreamingService.subscribeTimeline] が呼ばれるたびに新しい channelId で
/// connect を送っており、タブ切り替えや再購読のたびにサーバー側のチャンネルが
/// 積み上がっていた。同じノートが購読数だけ重複配信され、タイムライン画面の
/// 新着バッジが多重にカウントされる原因になっていたため、回帰を検知する。
///
/// `connect()` を呼ばないので WebSocket には接続されない。送信は握り潰されるが、
/// 購読の帳簿づけは接続の有無に関わらず同じコードを通る。
void main() {
  late StreamingService service;

  setUp(() {
    service = StreamingService(host: 'example.com', token: 'dummy');
  });

  tearDown(() {
    service.dispose();
  });

  group('subscribeTimeline', () {
    test('同じタイムラインを複数回購読してもチャンネルは1つだけ開く', () {
      service.subscribeTimeline('home');
      service.subscribeTimeline('home');
      service.subscribeTimeline('home');

      expect(service.debugChannelCount, 1);
    });

    test('同じタイムラインの購読者は同じコントローラーを共有する', () async {
      // broadcast の .stream は呼ぶたび別のラッパーを返すため、同一性ではなく
      // 「1つのコントローラーに束ねられているか」を閉じ方で確かめる。
      final first = service.subscribeTimeline('local');
      final second = service.subscribeTimeline('local');
      expect(first, isNotNull);
      expect(second, isNotNull);

      var firstDone = false;
      var secondDone = false;
      first!.listen(null, onDone: () => firstDone = true);
      second!.listen(null, onDone: () => secondDone = true);

      service.unsubscribeTimeline('local');
      service.unsubscribeTimeline('local');
      await Future<void>.delayed(Duration.zero);

      expect(firstDone, isTrue);
      expect(secondDone, isTrue);
    });

    test('タイムラインごとに別のチャンネルを開く', () {
      service.subscribeTimeline('home');
      service.subscribeTimeline('local');
      service.subscribeTimeline('channel:abc123');

      expect(service.debugChannelCount, 3);
    });

    test('未対応のタイムライン種別は null を返しチャンネルを開かない', () {
      expect(service.subscribeTimeline('unknown-type'), isNull);
      expect(service.debugChannelCount, 0);
    });
  });

  group('unsubscribeTimeline', () {
    test('購読者が残っている間はチャンネルを閉じない', () {
      service.subscribeTimeline('home');
      service.subscribeTimeline('home');

      service.unsubscribeTimeline('home');
      expect(service.debugChannelCount, 1);

      service.unsubscribeTimeline('home');
      expect(service.debugChannelCount, 0);
    });

    test('参照カウントが 0 になるとストリームが閉じる', () async {
      final stream = service.subscribeTimeline('home');
      var done = false;
      stream!.listen(null, onDone: () => done = true);

      service.unsubscribeTimeline('home');
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });

    test('解除したあと購読し直すとチャンネルを開き直す', () {
      service.subscribeTimeline('home');
      service.unsubscribeTimeline('home');
      expect(service.debugChannelCount, 0);

      service.subscribeTimeline('home');
      expect(service.debugChannelCount, 1);
    });

    test('購読していないタイムラインの解除は何もしない', () {
      service.subscribeTimeline('home');

      service.unsubscribeTimeline('local');
      service.unsubscribeTimeline('home');
      service.unsubscribeTimeline('home');

      expect(service.debugChannelCount, 0);
    });
  });
}
