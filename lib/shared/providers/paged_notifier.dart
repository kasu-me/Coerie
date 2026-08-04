import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_error_message.dart';

/// untilId でページングする一覧の共通状態。
class PagedState<T> {
  final List<T> items;
  final bool isLoading;

  /// 続きがある可能性。最後の取得件数がページサイズ未満なら false になる。
  final bool hasMore;
  final String? error;

  const PagedState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  /// [error] は省略時に null へ戻る（前回のエラーを持ち越さない）。
  PagedState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) => PagedState<T>(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: error,
  );
}

/// untilId ページングの取得・追加読み込み・再読み込みを共通化した StateNotifier。
///
/// 派生クラスは [fetchPage] で1ページぶんの取得だけを実装する。
/// 取得結果に手を加えたい場合（既読フラグの引き継ぎなど）は [mergeItems] を上書きする。
abstract class PagedNotifier<T> extends StateNotifier<PagedState<T>> {
  PagedNotifier() : super(PagedState<T>());

  /// 1ページの件数。取得件数がこれ未満なら [PagedState.hasMore] を false にする。
  int get pageSize => 20;

  /// 取得に失敗したときに [PagedState.error] へ入れる既定メッセージ。
  /// 通信断など原因を特定できた場合はそちらが優先される。
  String get errorFallback => defaultApiErrorMessage;

  /// [untilId] より古い1ページを取得する。null なら先頭から。
  Future<List<T>> fetchPage({String? untilId});

  /// ページングのカーソルに使う ID を返す。
  String cursorOf(T item);

  /// 取得した [fetched] を state に載せる前に加工する。既定では素通し。
  List<T> mergeItems(List<T> fetched) => fetched;

  Future<void> fetch({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final untilId = loadMore && state.items.isNotEmpty
          ? cursorOf(state.items.last)
          : null;
      final fetched = await fetchPage(untilId: untilId);
      final merged = mergeItems(fetched);
      state = state.copyWith(
        isLoading: false,
        items: loadMore ? [...state.items, ...merged] : merged,
        hasMore: fetched.length >= pageSize,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: apiErrorMessage(e, fallback: errorFallback),
      );
    }
  }

  Future<void> refresh() async {
    state = PagedState<T>();
    await fetch();
  }
}
