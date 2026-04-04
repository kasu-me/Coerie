import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/note_model.dart';
import '../../data/models/user_model.dart';
import '../timeline/widgets/note_card.dart';
import 'search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final int initialTab;
  final String? initialQuery;

  const SearchScreen({super.key, this.initialTab = 0, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _noteQueryController = TextEditingController();
  final _tagQueryController = TextEditingController();
  final _userQueryController = TextEditingController();
  final _hashtagQueryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    // 初期クエリがある場合はタブに応じて自動検索
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final q = widget.initialQuery!;
        switch (widget.initialTab) {
          case 0:
            _noteQueryController.text = q;
            ref.read(noteSearchProvider.notifier).search(q);
          case 1:
            _tagQueryController.text = q;
            ref.read(tagNoteSearchProvider.notifier).search(q);
          case 2:
            _userQueryController.text = q;
            ref.read(userSearchProvider.notifier).search(q);
          case 3:
            _hashtagQueryController.text = q;
            ref.read(hashtagSearchProvider.notifier).search(q);
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteQueryController.dispose();
    _tagQueryController.dispose();
    _userQueryController.dispose();
    _hashtagQueryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('検索'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(text: 'ノート'),
            Tab(text: 'タグ'),
            Tab(text: 'ユーザー'),
            Tab(text: 'ハッシュタグ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NoteSearchTab(controller: _noteQueryController),
          _TagNoteSearchTab(controller: _tagQueryController),
          _UserSearchTab(controller: _userQueryController),
          _HashtagSearchTab(controller: _hashtagQueryController),
        ],
      ),
    );
  }
}

// ---- 共通ウィジェット ----

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSearch;

  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSearch, child: const Text('検索')),
        ],
      ),
    );
  }
}

Widget _buildErrorWidget(
  BuildContext context,
  SearchError error,
  VoidCallback onRetry,
) {
  final isDisabled = error.type == SearchErrorType.disabled;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDisabled ? Icons.block : Icons.wifi_off,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            isDisabled ? 'この機能はサーバーで無効になっています' : error.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!isDisabled) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---- ノート検索タブ ----

class _NoteSearchTab extends ConsumerStatefulWidget {
  final TextEditingController controller;

  const _NoteSearchTab({required this.controller});

  @override
  ConsumerState<_NoteSearchTab> createState() => _NoteSearchTabState();
}

class _NoteSearchTabState extends ConsumerState<_NoteSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(noteSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(noteSearchProvider);
    return Column(
      children: [
        _SearchBar(
          controller: widget.controller,
          hintText: 'キーワードでノートを検索',
          onSearch: () => ref
              .read(noteSearchProvider.notifier)
              .search(widget.controller.text),
        ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(NoteSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(
        context,
        state.error!,
        () => ref
            .read(noteSearchProvider.notifier)
            .search(widget.controller.text),
      );
    }
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.notes.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するノートが見つかりませんでした'));
    }
    if (state.notes.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return _NoteList(
      notes: state.notes,
      isLoadingMore: state.isLoading,
      scrollController: _scrollController,
    );
  }
}

// ---- タグ検索タブ ----

class _TagNoteSearchTab extends ConsumerStatefulWidget {
  final TextEditingController controller;

  const _TagNoteSearchTab({required this.controller});

  @override
  ConsumerState<_TagNoteSearchTab> createState() => _TagNoteSearchTabState();
}

class _TagNoteSearchTabState extends ConsumerState<_TagNoteSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(tagNoteSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(tagNoteSearchProvider);
    return Column(
      children: [
        _SearchBar(
          controller: widget.controller,
          hintText: 'ハッシュタグでノートを検索（# 不要）',
          onSearch: () => ref
              .read(tagNoteSearchProvider.notifier)
              .search(widget.controller.text),
        ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(TagNoteSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(
        context,
        state.error!,
        () => ref
            .read(tagNoteSearchProvider.notifier)
            .search(widget.controller.text),
      );
    }
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.notes.isEmpty && state.tag.isNotEmpty) {
      return const Center(child: Text('該当するノートが見つかりませんでした'));
    }
    if (state.notes.isEmpty) {
      return const Center(
        child: Text('タグを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return _NoteList(
      notes: state.notes,
      isLoadingMore: state.isLoading,
      scrollController: _scrollController,
    );
  }
}

// ---- ユーザー検索タブ ----

class _UserSearchTab extends ConsumerStatefulWidget {
  final TextEditingController controller;

  const _UserSearchTab({required this.controller});

  @override
  ConsumerState<_UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends ConsumerState<_UserSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(userSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(userSearchProvider);
    return Column(
      children: [
        _SearchBar(
          controller: widget.controller,
          hintText: 'ユーザー名・表示名で検索',
          onSearch: () => ref
              .read(userSearchProvider.notifier)
              .search(widget.controller.text),
        ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(UserSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(
        context,
        state.error!,
        () => ref
            .read(userSearchProvider.notifier)
            .search(widget.controller.text),
      );
    }
    if (state.isLoading && state.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.users.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するユーザーが見つかりませんでした'));
    }
    if (state.users.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: state.users.length + (state.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.users.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _UserTile(user: state.users[index]);
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;

  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(user.acct, overflow: TextOverflow.ellipsis),
      onTap: () => context.push('/profile/${user.id}'),
    );
  }
}

// ---- ハッシュタグ検索タブ ----

class _HashtagSearchTab extends ConsumerStatefulWidget {
  final TextEditingController controller;

  const _HashtagSearchTab({required this.controller});

  @override
  ConsumerState<_HashtagSearchTab> createState() => _HashtagSearchTabState();
}

class _HashtagSearchTabState extends ConsumerState<_HashtagSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(hashtagSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(hashtagSearchProvider);
    return Column(
      children: [
        _SearchBar(
          controller: widget.controller,
          hintText: 'ハッシュタグを検索（# 不要）',
          onSearch: () => ref
              .read(hashtagSearchProvider.notifier)
              .search(widget.controller.text),
        ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(HashtagSearchState state) {
    if (state.error != null) {
      return _buildErrorWidget(
        context,
        state.error!,
        () => ref
            .read(hashtagSearchProvider.notifier)
            .search(widget.controller.text),
      );
    }
    if (state.isLoading && state.hashtags.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isLoading && state.hashtags.isEmpty && state.query.isNotEmpty) {
      return const Center(child: Text('該当するハッシュタグが見つかりませんでした'));
    }
    if (state.hashtags.isEmpty) {
      return const Center(
        child: Text('キーワードを入力して検索してください', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: state.hashtags.length + (state.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.hashtags.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final tag = state.hashtags[index];
        return ListTile(
          leading: const Icon(Icons.tag),
          title: Text('#$tag'),
          onTap: () {
            // タグタブに遷移してそのタグで検索
            // SearchScreen の TabController を操作する方法として
            // タグタブ（index=1）にフォーカスして自動検索するために
            // go_router の extra で情報を渡す
            context.push('/search', extra: {'tab': 1, 'query': tag});
          },
        );
      },
    );
  }
}

// ---- 共通ノートリスト ----

class _NoteList extends StatelessWidget {
  final List<NoteModel> notes;
  final bool isLoadingMore;
  final ScrollController scrollController;

  const _NoteList({
    required this.notes,
    required this.isLoadingMore,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: notes.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == notes.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return NoteCard(note: notes[index]);
      },
    );
  }
}
