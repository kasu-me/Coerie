import 'package:flutter/widgets.dart';

/// 一覧の末尾に近づいたら追加読み込みを呼ぶ、無限スクロールの共通実装。
///
/// 各画面が `ScrollController` の生成・リスナー登録・破棄・しきい値判定を
/// 手書きしており、同じコードが13箇所に散っていた。判定の書き方が揃わず、
/// `.position` の安全な読み方（下記）を知っている箇所と知らない箇所が
/// 混在していたため、判定をここに閉じ込める。
///
/// 使い方:
///
/// ```dart
/// class _FooScreenState extends ConsumerState<FooScreen>
///     with InfiniteScrollMixin<FooScreen> {
///   @override
///   void onLoadMore() => ref.read(fooProvider.notifier).fetch(loadMore: true);
///
///   @override
///   Widget build(BuildContext context) =>
///       ListView(controller: scrollController, children: [...]);
/// }
/// ```
///
/// [scrollController] の生成と破棄はこの mixin が持つ。State 側で
/// `dispose()` する必要はない（二重破棄になる）。
mixin InfiniteScrollMixin<T extends StatefulWidget> on State<T> {
  /// リストに渡すコントローラー。破棄はこの mixin が行う。
  final ScrollController scrollController = ScrollController();

  /// 末尾からこの距離（論理ピクセル）まで来たら [onLoadMore] を呼ぶ。
  double get loadMoreExtent => 300;

  /// 追加読み込みを開始する。
  ///
  /// スクロール中に何度も呼ばれるため、多重実行の抑止は呼び出し先が持つこと
  /// （`PagedNotifier.fetch` は `isLoading` / `hasMore` で弾く）。
  void onLoadMore();

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_handleScroll);
    scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    // `.position` は ScrollPosition がちょうど1つのときしか読めない。
    // 0個（まだリストに未アタッチ）でも、2個以上（同じコントローラーを
    // 複数のスクロールビューが共有している。タブ切り替えの過渡期などに
    // 一瞬起きる）でも例外を投げる。ここで投げるとリスナーが例外を出し続け、
    // 以降 onLoadMore に到達しなくなって追加読み込みが恒久的に止まる。
    if (scrollController.positions.length != 1) return;

    final position = scrollController.position;
    // レイアウト確定前は pixels / maxScrollExtent の読み出し自体が投げる。
    if (!position.hasPixels || !position.hasContentDimensions) return;

    if (position.pixels >= position.maxScrollExtent - loadMoreExtent) {
      onLoadMore();
    }
  }
}
