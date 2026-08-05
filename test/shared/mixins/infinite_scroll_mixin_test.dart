import 'package:coerie/shared/mixins/infinite_scroll_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 無限スクロールの共通判定を確かめる。
///
/// 特に検証したいのは「`.position` を安全に読む」こと。ScrollPosition が
/// 0個（未アタッチ）でも 2個以上（同じコントローラーを複数のスクロールビューが
/// 共有）でも `.position` は例外を投げる。リスナー内で投げると以降
/// onLoadMore に到達せず、追加読み込みが恒久的に止まる。
class _Host extends StatefulWidget {
  final VoidCallback onLoadMore;

  /// true にすると同じコントローラーを2つの ListView が共有する。
  final bool duplicateAttach;

  const _Host({required this.onLoadMore, this.duplicateAttach = false});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with InfiniteScrollMixin<_Host> {
  @override
  void onLoadMore() => widget.onLoadMore();

  Widget _list() => ListView.builder(
    controller: scrollController,
    itemCount: 100,
    itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: widget.duplicateAttach
        ? Column(
            children: [
              Expanded(child: _list()),
              Expanded(child: _list()),
            ],
          )
        : _list(),
  );
}

void main() {
  testWidgets('末尾付近までスクロールすると onLoadMore が呼ばれる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Host(onLoadMore: () => calls++));

    expect(calls, 0, reason: '初期表示だけでは呼ばれない');

    final state = tester.state<_HostState>(find.byType(_Host));
    state.scrollController.jumpTo(
      state.scrollController.position.maxScrollExtent,
    );
    await tester.pump();

    expect(calls, greaterThan(0));
  });

  testWidgets('末尾から遠い位置では onLoadMore が呼ばれない', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Host(onLoadMore: () => calls++));

    final state = tester.state<_HostState>(find.byType(_Host));
    state.scrollController.jumpTo(100);
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('ScrollPosition が複数でも例外を投げず、判定を見送る', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _Host(onLoadMore: () => calls++, duplicateAttach: true),
    );

    final state = tester.state<_HostState>(find.byType(_Host));
    expect(state.scrollController.positions.length, 2);

    // 例外が漏れると以降 onLoadMore に到達しなくなる。ここでは何も起きないのが正。
    state.scrollController.positions.first.jumpTo(1000);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(calls, 0);
  });

  testWidgets('dispose でコントローラーが破棄される', (tester) async {
    await tester.pumpWidget(_Host(onLoadMore: () {}));
    final controller = tester
        .state<_HostState>(find.byType(_Host))
        .scrollController;

    await tester.pumpWidget(const SizedBox());

    // 破棄済みのコントローラーはリスナー追加で投げる。
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
