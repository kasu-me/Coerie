import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/error_view.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  List<FavoriteModel> _favorites = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();

  /// 次ページの取得に使うカーソル。
  /// ノートのIDではなくお気に入りレコードのIDを渡す（[FavoriteModel] 参照）。
  /// `i/favorites` は新しい順に返すため、末尾が最も古いレコードになる。
  String? get _oldestFavoriteId =>
      _favorites.isEmpty ? null : _favorites.last.id;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoading &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _favorites = [];
      _hasMore = true;
      _error = null;
      _isLoading = true;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final favorites = await api.getFavorites(limit: 20);
      if (mounted) {
        setState(() {
          _favorites = favorites;
          _hasMore = favorites.length >= 20;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'お気に入りを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_favorites.isEmpty) return;
    setState(() => _isLoading = true);
    final api = ref.read(misskeyApiProvider);
    // ここで return する場合は try/finally を通らないため、
    // _isLoading を自前で戻さないと以降の追加読み込みが止まる。
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final more = await api.getFavorites(
        limit: 20,
        untilId: _oldestFavoriteId,
      );
      if (mounted) {
        setState(() {
          _favorites = [..._favorites, ...more];
          _hasMore = more.length >= 20;
        });
      }
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: '読み込みに失敗しました');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入り'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _favorites.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _favorites.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_favorites.isEmpty) {
      return const Center(child: Text('お気に入りがありません'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _favorites.length + (_isLoading || _hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _favorites.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final favorite = _favorites[index];
          return NoteCard(
            key: ValueKey(favorite.id),
            note: favorite.note,
            onUnfavorited: () {
              if (mounted) {
                setState(
                  () => _favorites.removeWhere((f) => f.id == favorite.id),
                );
              }
            },
          );
        },
      ),
    );
  }
}
