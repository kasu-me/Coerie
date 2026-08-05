import 'dart:async';

import 'package:coerie/core/errors/api_error_message.dart';
import 'package:coerie/shared/providers/paged_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取得の完了タイミングをテストから制御できる [PagedNotifier]。
///
/// `fetchPage` は Completer を返し、`complete...` を呼ぶまで解決しない。
/// これで「飛行中に refresh が入る」状況を再現する。
class _FakeNotifier extends PagedNotifier<String> {
  /// 未解決の取得要求。呼ばれた順に積まれる。
  final List<Completer<List<String>>> pending = [];

  /// fetchPage に渡された untilId の履歴。
  final List<String?> receivedUntilIds = [];

  @override
  int get pageSize => 2;

  @override
  String get errorFallback => '取得に失敗しました';

  @override
  String cursorOf(String item) => item;

  @override
  Future<List<String>> fetchPage({String? untilId}) {
    receivedUntilIds.add(untilId);
    final completer = Completer<List<String>>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  late _FakeNotifier notifier;

  setUp(() => notifier = _FakeNotifier());

  group('通常のページング', () {
    test('取得した件数が pageSize 以上なら hasMore が真のまま', () async {
      final future = notifier.fetch();
      notifier.pending[0].complete(['a', 'b']);
      await future;

      expect(notifier.state.items, ['a', 'b']);
      expect(notifier.state.hasMore, isTrue);
      expect(notifier.state.isLoading, isFalse);
    });

    test('取得した件数が pageSize 未満なら hasMore が偽になる', () async {
      final future = notifier.fetch();
      notifier.pending[0].complete(['a']);
      await future;

      expect(notifier.state.hasMore, isFalse);
    });

    test('追加読み込みは末尾要素をカーソルに使い、結果を後ろへ足す', () async {
      final first = notifier.fetch();
      notifier.pending[0].complete(['a', 'b']);
      await first;

      final second = notifier.fetch(loadMore: true);
      notifier.pending[1].complete(['c', 'd']);
      await second;

      expect(notifier.receivedUntilIds, [null, 'b']);
      expect(notifier.state.items, ['a', 'b', 'c', 'd']);
    });

    test('失敗するとエラー文言が入り、ローディングが解除される', () async {
      final future = notifier.fetch();
      notifier.pending[0].completeError(Exception('boom'));
      await future;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, '取得に失敗しました');
      expect(notifier.state.error, isNot(contains('Exception')));
    });
  });

  group('refresh との競合', () {
    test('飛行中の追加読み込みの結果は破棄される', () async {
      final first = notifier.fetch();
      notifier.pending[0].complete(['a', 'b']);
      await first;

      // 追加読み込みを開始し、解決させないまま refresh を割り込ませる。
      final staleLoadMore = notifier.fetch(loadMore: true);
      final refresh = notifier.refresh();

      // refresh 側の取得（3回目）を先に解決させる。
      notifier.pending[2].complete(['x', 'y']);
      await refresh;

      // 遅れて返ってきた古い追加読み込み。
      notifier.pending[1].complete(['c', 'd']);
      await staleLoadMore;

      expect(notifier.state.items, [
        'x',
        'y',
      ], reason: '古いページが新しい一覧の末尾に継ぎ足されてはいけない');
    });

    test('飛行中の取得が失敗しても、refresh 後の状態を汚さない', () async {
      final stale = notifier.fetch();
      final refresh = notifier.refresh();

      notifier.pending[1].complete(['x', 'y']);
      await refresh;

      notifier.pending[0].completeError(Exception('boom'));
      await stale;

      expect(notifier.state.error, isNull);
      expect(notifier.state.items, ['x', 'y']);
      expect(notifier.state.isLoading, isFalse);
    });

    test('古い結果の hasMore で上書きされない', () async {
      final stale = notifier.fetch();
      final refresh = notifier.refresh();

      // refresh 側は pageSize 未満 → hasMore は偽になるべき。
      notifier.pending[1].complete(['x']);
      await refresh;
      expect(notifier.state.hasMore, isFalse);

      // 古い方は pageSize 以上だが、これで真に戻してはいけない。
      notifier.pending[0].complete(['a', 'b']);
      await stale;

      expect(notifier.state.hasMore, isFalse);
    });
  });

  group('破棄後の完了', () {
    test('破棄後に取得が完了しても例外を投げない', () async {
      final future = notifier.fetch();
      notifier.dispose();

      notifier.pending[0].complete(['a', 'b']);

      await expectLater(future, completes);
    });

    test('破棄後に取得が失敗しても例外を投げない', () async {
      final future = notifier.fetch();
      notifier.dispose();

      notifier.pending[0].completeError(const AppException('失敗'));

      await expectLater(future, completes);
    });
  });
}
