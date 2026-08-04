import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/channel_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/utils/color_utils.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/error_view.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabLabels = ['検索', 'トレンド', 'お気に入り', 'フォロー中', '管理中'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('チャンネル'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _SearchTab(),
          const _FeaturedTab(),
          const _FavoritesTab(),
          const _FollowedTab(),
          const _OwnedTab(),
        ],
      ),
    );
  }
}

// ---- Channel list tile ----

class _ChannelTile extends StatelessWidget {
  final ChannelModel channel;
  final List<PopupMenuEntry<String>>? menuItems;
  final void Function(String)? onMenuSelected;

  const _ChannelTile({
    required this.channel,
    this.menuItems,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final name = channel.name;
    final description = channel.description;
    final bannerUrl = channel.bannerUrl;
    final usersCount = channel.usersCount;
    final notesCount = channel.notesCount;
    final isArchived = channel.isArchived;

    final channelColor =
        channelColorFromHex(channel.color ?? '#888888') ??
        Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: bannerUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: bannerUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _colorIcon(channelColor),
              ),
            )
          : _colorIcon(channelColor),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          if (isArchived) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'アーカイブ済',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
      subtitle: description != null && description.isNotEmpty
          ? Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Text(
              'ユーザー $usersCount ・ ノート $notesCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
      trailing: menuItems != null
          ? PopupMenuButton<String>(
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems!,
            )
          : null,
      onTap: () => context.push('/channels/${channel.id}', extra: channel),
    );
  }

  Widget _colorIcon(Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(Icons.tv, color: color),
    );
  }
}

// ---- Search tab ----

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  List<ChannelModel> _results = [];
  bool _isLoading = false;
  String? _error;
  bool _searched = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await api.searchChannels(query: query.trim());
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'チャンネルを検索できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SearchBar(
            controller: _searchController,
            hintText: 'チャンネルを検索',
            leading: const Icon(Icons.search),
            trailing: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _searched = false;
                    });
                  },
                ),
            ],
            onSubmitted: _search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: () => _search(_searchController.text),
      );
    }
    if (!_searched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('チャンネル名・概要で検索できます'),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('チャンネルが見つかりませんでした'));
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
      ),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _ChannelTile(channel: _results[i]),
    );
  }
}

// ---- Trending tab ----

class _FeaturedTab extends ConsumerStatefulWidget {
  const _FeaturedTab();

  @override
  ConsumerState<_FeaturedTab> createState() => _FeaturedTabState();
}

class _FeaturedTabState extends ConsumerState<_FeaturedTab>
    with AutomaticKeepAliveClientMixin {
  List<ChannelModel> _items = [];
  bool _isLoading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) {
        setState(() => _error = 'ログインが必要です');
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await api.getChannelsFeatured();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'チャンネルを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(child: Text('トレンドのチャンネルはありません'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _ChannelTile(channel: _items[i]),
      ),
    );
  }
}

// ---- Favorites tab ----

class _FavoritesTab extends ConsumerStatefulWidget {
  const _FavoritesTab();

  @override
  ConsumerState<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<_FavoritesTab>
    with AutomaticKeepAliveClientMixin {
  List<ChannelModel> _items = [];
  bool _isLoading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) {
        setState(() => _error = 'ログインが必要です');
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await api.getChannelsMyFavorites();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'チャンネルを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(child: Text('お気に入りのチャンネルはありません'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _ChannelTile(channel: _items[i]),
      ),
    );
  }
}

// ---- Followed tab ----

class _FollowedTab extends ConsumerStatefulWidget {
  const _FollowedTab();

  @override
  ConsumerState<_FollowedTab> createState() => _FollowedTabState();
}

class _FollowedTabState extends ConsumerState<_FollowedTab>
    with AutomaticKeepAliveClientMixin {
  List<ChannelModel> _items = [];
  bool _isLoading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) {
        setState(() => _error = 'ログインが必要です');
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await api.getChannelsFollowed();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'チャンネルを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(child: Text('フォロー中のチャンネルはありません'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _ChannelTile(channel: _items[i]),
      ),
    );
  }
}

// ---- Owned tab ----

class _OwnedTab extends ConsumerStatefulWidget {
  const _OwnedTab();

  @override
  ConsumerState<_OwnedTab> createState() => _OwnedTabState();
}

class _OwnedTabState extends ConsumerState<_OwnedTab>
    with AutomaticKeepAliveClientMixin {
  List<ChannelModel> _items = [];
  bool _isLoading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) {
        setState(() => _error = 'ログインが必要です');
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await api.getChannelsOwned();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'チャンネルを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ChannelEditSheet(onSaved: _load),
    );
  }

  void _showEditSheet(ChannelModel channel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ChannelEditSheet(channel: channel, onSaved: _load),
    );
  }

  Future<void> _archiveChannel(ChannelModel channel) async {
    final confirmed = await confirmAction(
      context,
      ref,
      title: 'チャンネルをアーカイブ',
      message: '「${channel.name}」をアーカイブしますか？アーカイブされたチャンネルは非公開になります。',
      confirmLabel: 'アーカイブ',
    );
    if (!confirmed || !mounted) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.archiveChannel(channel.id);
      await _load();
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: 'アーカイブに失敗しました');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateSheet,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tv, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('管理中のチャンネルはありません'),
            SizedBox(height: 8),
            Text(
              '右下の + ボタンでチャンネルを作成できます',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 80,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = _items[i];
          return _ChannelTile(
            channel: item,
            menuItems: [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined),
                    SizedBox(width: 8),
                    Text('編集'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'アーカイブ',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
            onMenuSelected: (value) {
              if (value == 'edit') _showEditSheet(item);
              if (value == 'archive') _archiveChannel(item);
            },
          );
        },
      ),
    );
  }
}

// ---- Error view helper ----

// ---- Channel create/edit bottom sheet ----

class _ChannelEditSheet extends ConsumerStatefulWidget {
  final ChannelModel? channel;
  final VoidCallback onSaved;

  const _ChannelEditSheet({this.channel, required this.onSaved});

  @override
  ConsumerState<_ChannelEditSheet> createState() => _ChannelEditSheetState();
}

class _ChannelEditSheetState extends ConsumerState<_ChannelEditSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _colorController = TextEditingController();
  bool _isSensitive = false;
  bool _allowRenoteToExternal = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final ch = widget.channel;
    if (ch != null) {
      _nameController.text = ch.name;
      _descriptionController.text = ch.description ?? '';
      _colorController.text = ch.color ?? '#000000';
      _isSensitive = ch.isSensitive;
      _allowRenoteToExternal = ch.allowRenoteToExternal;
    } else {
      _colorController.text = '#000000';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('チャンネル名を入力してください')));
      return;
    }
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    setState(() => _isSaving = true);
    try {
      if (widget.channel == null) {
        await api.createChannel(
          name: name,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          color: _colorController.text.trim().isEmpty
              ? '#000000'
              : _colorController.text.trim(),
          isSensitive: _isSensitive,
          allowRenoteToExternal: _allowRenoteToExternal,
        );
      } else {
        await api.updateChannel(
          channelId: widget.channel!.id,
          name: name,
          description: _descriptionController.text.trim(),
          color: _colorController.text.trim().isEmpty
              ? '#000000'
              : _colorController.text.trim(),
          isSensitive: _isSensitive,
          allowRenoteToExternal: _allowRenoteToExternal,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: '保存に失敗しました');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.channel != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'チャンネルを編集' : '新しいチャンネルを作成',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: _save,
                    child: Text(isEdit ? '保存' : '作成'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'チャンネル名 *',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: !isEdit,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '説明',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(
                    labelText: 'カラー（#RRGGBB）',
                    border: OutlineInputBorder(),
                    hintText: '#000000',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isSensitive,
                  onChanged: (v) => setState(() => _isSensitive = v),
                  title: const Text('センシティブなチャンネル'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _allowRenoteToExternal,
                  onChanged: (v) => setState(() => _allowRenoteToExternal = v),
                  title: const Text('外部へのリノートを許可'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
