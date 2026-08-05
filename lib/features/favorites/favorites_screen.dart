import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../shared/mixins/infinite_scroll_mixin.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/paged_notifier.dart';
import '../timeline/widgets/note_card.dart';
import '../../shared/widgets/error_view.dart';

class _FavoritesNotifier extends PagedNotifier<FavoriteModel> {
  final Ref _ref;

  _FavoritesNotifier(this._ref) {
    fetch();
  }

  @override
  String get errorFallback => 'お気に入りを取得できませんでした';

  /// カーソルはノートIDではなくお気に入りレコードのID。
  /// 取り違えるとページングが壊れる（[FavoriteModel] のコメント参照）。
  @override
  String cursorOf(FavoriteModel item) => item.id;

  @override
  Future<List<FavoriteModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return const [];
    return api.getFavorites(limit: pageSize, untilId: untilId);
  }

  /// 一覧から1件取り除く（お気に入り解除直後の反映用）。再取得はしない。
  void removeLocally(String favoriteId) {
    state = state.copyWith(
      items: state.items.where((f) => f.id != favoriteId).toList(),
    );
  }
}

final _favoritesProvider =
    StateNotifierProvider.autoDispose<
      _FavoritesNotifier,
      PagedState<FavoriteModel>
    >((ref) => _FavoritesNotifier(ref));

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with InfiniteScrollMixin<FavoritesScreen> {
  @override
  void onLoadMore() =>
      ref.read(_favoritesProvider.notifier).fetch(loadMore: true);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_favoritesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入り'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
            onPressed: () => ref.read(_favoritesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(PagedState<FavoriteModel> state) {
    final notifier = ref.read(_favoritesProvider.notifier);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error!, onRetry: notifier.refresh);
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('お気に入りがありません'));
    }
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            state.items.length + (state.isLoading || state.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final favorite = state.items[index];
          return NoteCard(
            key: ValueKey(favorite.id),
            note: favorite.note,
            onUnfavorited: () => notifier.removeLocally(favorite.id),
          );
        },
      ),
    );
  }
}
