import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/gallery_post_model.dart';
import '../../../data/remote/misskey_api.dart';
import '../../../shared/providers/misskey_api_provider.dart';
import '../../../shared/providers/paged_notifier.dart';

typedef GalleryFetcher =
    Future<List<GalleryPostModel>> Function(MisskeyApi api, String? untilId);

/// ギャラリー詳細画面からの戻り値。
///
/// [post] が非 null なら投稿の内容（いいね状態・編集結果）が更新されたことを示す。
/// [deletedId] が非 null ならその ID の投稿が削除されたことを示す。
/// 呼び出し元の一覧はこれを見て自分のキャッシュに反映する。
class GalleryDetailResult {
  final GalleryPostModel? post;
  final String? deletedId;

  const GalleryDetailResult.updated(GalleryPostModel this.post) : deletedId = null;
  const GalleryDetailResult.deleted(String this.deletedId) : post = null;
}

// ---- 新着（gallery/posts, 無限スクロール） ----

final galleryNewProvider = StateNotifierProvider.autoDispose
    .family<GalleryPostsNotifier, PagedState<GalleryPostModel>, String>(
      (ref, accountId) => GalleryPostsNotifier(
        ref,
        fetcher: (api, untilId) => api.getGalleryPosts(untilId: untilId),
      ),
    );

// ---- おすすめ（gallery/featured, untilId のみ対応・無限スクロール） ----

final galleryFeaturedProvider = StateNotifierProvider.autoDispose
    .family<GalleryPostsNotifier, PagedState<GalleryPostModel>, String>(
      (ref, accountId) => GalleryPostsNotifier(
        ref,
        fetcher: (api, untilId) =>
            api.getFeaturedGalleryPosts(untilId: untilId),
      ),
    );

// ---- 自分の投稿（i/gallery/posts, `read:gallery`, 無限スクロール） ----

final galleryMineProvider = StateNotifierProvider.autoDispose
    .family<GalleryPostsNotifier, PagedState<GalleryPostModel>, String>(
      (ref, accountId) => GalleryPostsNotifier(
        ref,
        fetcher: (api, untilId) => api.getMyGalleryPosts(untilId: untilId),
      ),
    );

// ---- 人気（gallery/popular, 引数なし固定10件・読み切り） ----
//
// PagedNotifier をそのまま使うが、fetchPage は untilId を無視して常に
// 同じ10件を返す。追加読み込み（loadMore）は呼び出し側で行わない前提。
// 取得件数(最大10)が既定ページサイズ(20)未満になるため、hasMore は自動的に
// false になり、万一 loadMore が呼ばれても重複追加は起きない。
final galleryPopularProvider = StateNotifierProvider.autoDispose
    .family<GalleryPostsNotifier, PagedState<GalleryPostModel>, String>(
      (ref, accountId) => GalleryPostsNotifier(
        ref,
        fetcher: (api, untilId) => api.getPopularGalleryPosts(),
      ),
    );

// ---- 指定ユーザーの投稿（users/gallery/posts, 無限スクロール） ----

final galleryUserPostsProvider = StateNotifierProvider.autoDispose
    .family<GalleryPostsNotifier, PagedState<GalleryPostModel>, String>(
      (ref, userId) => GalleryPostsNotifier(
        ref,
        fetcher: (api, untilId) =>
            api.getUserGalleryPosts(userId: userId, untilId: untilId),
      ),
    );

class GalleryPostsNotifier extends PagedNotifier<GalleryPostModel> {
  final Ref _ref;
  final GalleryFetcher _fetcher;

  GalleryPostsNotifier(this._ref, {required GalleryFetcher fetcher})
    : _fetcher = fetcher {
    fetch();
  }

  @override
  String cursorOf(GalleryPostModel item) => item.id;

  @override
  Future<List<GalleryPostModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    return _fetcher(api, untilId);
  }

  /// 詳細画面などから戻ってきた最新の投稿状態を一覧に反映する。
  void applyUpdate(GalleryPostModel updated) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id == updated.id) updated else item,
      ],
    );
  }

  /// 削除された投稿を一覧から取り除く。
  void removePost(String postId) {
    state = state.copyWith(
      items: state.items.where((e) => e.id != postId).toList(),
    );
  }
}

// ---- いいねした投稿（i/gallery/likes, `read:gallery-likes`, 無限スクロール） ----
//
// **ページングのカーソルには外側の [GalleryLikeModel.id] を使う。**
// `post.id` を使うとページングが壊れる。

final galleryLikedProvider = StateNotifierProvider.autoDispose
    .family<GalleryLikedNotifier, PagedState<GalleryLikeModel>, String>(
      (ref, accountId) => GalleryLikedNotifier(ref),
    );

class GalleryLikedNotifier extends PagedNotifier<GalleryLikeModel> {
  final Ref _ref;
  GalleryLikedNotifier(this._ref) {
    fetch();
  }

  @override
  String cursorOf(GalleryLikeModel item) => item.id;

  @override
  Future<List<GalleryLikeModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    return api.getLikedGalleryPosts(untilId: untilId);
  }

  /// 詳細画面から戻ってきた投稿状態を反映する。
  /// いいねが外された場合はこの一覧から取り除く。
  void applyUpdate(GalleryPostModel updated) {
    if (updated.isLiked == false) {
      state = state.copyWith(
        items: state.items.where((e) => e.post.id != updated.id).toList(),
      );
      return;
    }
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.post.id == updated.id)
            GalleryLikeModel(id: item.id, post: updated)
          else
            item,
      ],
    );
  }

  /// 削除された投稿を一覧から取り除く。
  void removePost(String postId) {
    state = state.copyWith(
      items: state.items.where((e) => e.post.id != postId).toList(),
    );
  }
}
