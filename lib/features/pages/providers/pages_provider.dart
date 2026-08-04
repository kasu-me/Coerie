import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/page_model.dart';
import '../../../shared/providers/misskey_api_provider.dart';
import '../../../shared/providers/paged_notifier.dart';

/// ページ系一覧の共通基底。
///
/// [PagedNotifier] は失敗時に `e.toString()` しか保持しないため、
/// `showApiErrorSnackBar` / `apiErrorMessage` に渡せる生の例外を
/// [lastError] に控えておく。
abstract class _PagesPagedNotifier<T> extends PagedNotifier<T> {
  /// 直近の取得で発生した例外（成功時は null）。
  Object? lastError;

  /// [body] を実行しつつ、例外を [lastError] に記録して再送出する。
  Future<List<T>> guarded(Future<List<T>> Function() body) async {
    try {
      final result = await body();
      lastError = null;
      return result;
    } catch (e) {
      lastError = e;
      rethrow;
    }
  }
}

/// 自分のページ一覧（`i/pages`、`read:pages`）。
class MyPagesNotifier extends _PagesPagedNotifier<PageModel> {
  final Ref _ref;

  MyPagesNotifier(this._ref) {
    fetch();
  }

  @override
  String cursorOf(PageModel item) => item.id;

  @override
  Future<List<PageModel>> fetchPage({String? untilId}) => guarded(() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];
    return api.getMyPages(limit: pageSize, untilId: untilId);
  });

  /// 一覧から1件取り除く（削除直後の反映用）。再取得はしない。
  void removeLocally(String pageId) {
    state = state.copyWith(
      items: state.items.where((p) => p.id != pageId).toList(),
    );
  }
}

final myPagesProvider = StateNotifierProvider.autoDispose
    .family<MyPagesNotifier, PagedState<PageModel>, String>(
      (ref, _) => MyPagesNotifier(ref),
    );

/// いいねしたページ一覧（`i/page-likes`、`read:page-likes`）。
///
/// 戻り値は `{ id, page }` のラッパーで、**ページングのカーソルには
/// 外側の [PageLikeModel.id] を使う**。`page.id` を使うとページングが壊れる。
class LikedPagesNotifier extends _PagesPagedNotifier<PageLikeModel> {
  final Ref _ref;

  LikedPagesNotifier(this._ref) {
    fetch();
  }

  @override
  String cursorOf(PageLikeModel item) => item.id;

  @override
  Future<List<PageLikeModel>> fetchPage({String? untilId}) => guarded(() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];
    return api.getLikedPages(limit: pageSize, untilId: untilId);
  });
}

final likedPagesProvider = StateNotifierProvider.autoDispose
    .family<LikedPagesNotifier, PagedState<PageLikeModel>, String>(
      (ref, _) => LikedPagesNotifier(ref),
    );

/// 指定ユーザーのページ一覧（`users/pages`、権限不要）。
class UserPagesNotifier extends _PagesPagedNotifier<PageModel> {
  final Ref _ref;
  final String userId;

  UserPagesNotifier(this._ref, this.userId) {
    fetch();
  }

  @override
  String cursorOf(PageModel item) => item.id;

  @override
  Future<List<PageModel>> fetchPage({String? untilId}) => guarded(() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];
    return api.getUserPages(userId: userId, limit: pageSize, untilId: untilId);
  });
}

final userPagesProvider = StateNotifierProvider.autoDispose
    .family<UserPagesNotifier, PagedState<PageModel>, String>(
      (ref, userId) => UserPagesNotifier(ref, userId),
    );

/// おすすめのページ（`pages/featured`）。
///
/// **引数なし・固定10件**でページングが無いため、読み切り＋Pull-to-Refresh で扱う。
final featuredPagesProvider = FutureProvider.autoDispose<List<PageModel>>((
  ref,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return const [];
  return api.getFeaturedPages();
});
