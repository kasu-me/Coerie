import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabLabels = [
    '\u691c\u7d22',
    '\u30c8\u30ec\u30f3\u30c9',
    '\u304a\u6c17\u306b\u5165\u308a',
    '\u30d5\u30a9\u30ed\u30fc\u4e2d',
    '\u7ba1\u7406\u4e2d',
  ];

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
        title: const Text('\u30c1\u30e3\u30f3\u30cd\u30eb'),
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
  final Map<String, dynamic> channel;
  final List<PopupMenuEntry<String>>? menuItems;
  final void Function(String)? onMenuSelected;

  const _ChannelTile({
    required this.channel,
    this.menuItems,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final name = channel['name'] as String? ?? '';
    final description = channel['description'] as String?;
    final bannerUrl = channel['bannerUrl'] as String?;
    final color = channel['color'] as String? ?? '#888888';
    final usersCount = channel['usersCount'] as int? ?? 0;
    final notesCount = channel['notesCount'] as int? ?? 0;
    final isArchived = channel['isArchived'] as bool? ?? false;

    Color channelColor;
    try {
      final hex = color.replaceAll('#', '');
      channelColor = Color(
        int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16),
      );
    } catch (_) {
      channelColor = Theme.of(context).colorScheme.primary;
    }

    return ListTile(
      leading: bannerUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: bannerUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _colorIcon(channelColor),
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
                '\u30a2\u30fc\u30ab\u30a4\u30d6\u6e08',
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
              '\u30e6\u30fc\u30b6\u30fc $usersCount \u30fb \u30ce\u30fc\u30c8 $notesCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
      trailing: menuItems != null
          ? PopupMenuButton<String>(
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems!,
            )
          : null,
      onTap: () => context.push('/channels/${channel['id']}', extra: channel),
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
  List<Map<String, dynamic>> _results = [];
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
      if (mounted) setState(() => _error = e.toString());
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
            hintText: '\u30c1\u30e3\u30f3\u30cd\u30eb\u3092\u691c\u7d22',
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '\u30a8\u30e9\u30fc\u304c\u767a\u751f\u3057\u307e\u3057\u305f',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _search(_searchController.text),
              child: const Text('\u518d\u8a66\u884c'),
            ),
          ],
        ),
      );
    }
    if (!_searched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '\u30c1\u30e3\u30f3\u30cd\u30eb\u540d\u30fb\u6982\u8981\u3067\u691c\u7d22\u3067\u304d\u307e\u3059',
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          '\u30c1\u30e3\u30f3\u30cd\u30eb\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f',
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
      ),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
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
  List<Map<String, dynamic>> _items = [];
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
        setState(
          () =>
              _error = '\u30ed\u30b0\u30a4\u30f3\u304c\u5fc5\u8981\u3067\u3059',
        );
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
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '\u30c8\u30ec\u30f3\u30c9\u306e\u30c1\u30e3\u30f3\u30cd\u30eb\u306f\u3042\u308a\u307e\u305b\u3093',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
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
  List<Map<String, dynamic>> _items = [];
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
        setState(
          () =>
              _error = '\u30ed\u30b0\u30a4\u30f3\u304c\u5fc5\u8981\u3067\u3059',
        );
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
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '\u304a\u6c17\u306b\u5165\u308a\u306e\u30c1\u30e3\u30f3\u30cd\u30eb\u306f\u3042\u308a\u307e\u305b\u3093',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
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
  List<Map<String, dynamic>> _items = [];
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
        setState(
          () =>
              _error = '\u30ed\u30b0\u30a4\u30f3\u304c\u5fc5\u8981\u3067\u3059',
        );
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
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '\u30d5\u30a9\u30ed\u30fc\u4e2d\u306e\u30c1\u30e3\u30f3\u30cd\u30eb\u306f\u3042\u308a\u307e\u305b\u3093',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
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
  List<Map<String, dynamic>> _items = [];
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
        setState(
          () =>
              _error = '\u30ed\u30b0\u30a4\u30f3\u304c\u5fc5\u8981\u3067\u3059',
        );
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
      if (mounted) setState(() => _error = e.toString());
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

  void _showEditSheet(Map<String, dynamic> channel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ChannelEditSheet(channel: channel, onSaved: _load),
    );
  }

  Future<void> _archiveChannel(Map<String, dynamic> channel) async {
    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            '\u30c1\u30e3\u30f3\u30cd\u30eb\u3092\u30a2\u30fc\u30ab\u30a4\u30d6',
          ),
          content: Text(
            '\u300c${channel['name']}\u300d\u3092\u30a2\u30fc\u30ab\u30a4\u30d6\u3057\u307e\u3059\u304b\uff1f\u30a2\u30fc\u30ab\u30a4\u30d6\u3055\u308c\u305f\u30c1\u30e3\u30f3\u30cd\u30eb\u306f\u975e\u516c\u958b\u306b\u306a\u308a\u307e\u3059\u3002',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('\u30ad\u30e3\u30f3\u30bb\u30eb'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('\u30a2\u30fc\u30ab\u30a4\u30d6'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.archiveChannel(channel['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u30a2\u30fc\u30ab\u30a4\u30d6\u306b\u5931\u6557\u3057\u307e\u3057\u305f: $e',
            ),
          ),
        );
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
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tv, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '\u7ba1\u7406\u4e2d\u306e\u30c1\u30e3\u30f3\u30cd\u30eb\u306f\u3042\u308a\u307e\u305b\u3093',
            ),
            SizedBox(height: 8),
            Text(
              '\u53f3\u4e0b\u306e + \u30dc\u30bf\u30f3\u3067\u30c1\u30e3\u30f3\u30cd\u30eb\u3092\u4f5c\u6210\u3067\u304d\u307e\u3059',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 80,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
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
                    Text('\u7de8\u96c6'),
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
                      '\u30a2\u30fc\u30ab\u30a4\u30d6',
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

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '\u30a8\u30e9\u30fc\u304c\u767a\u751f\u3057\u307e\u3057\u305f',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(error, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('\u518d\u8a66\u884c'),
          ),
        ],
      ),
    );
  }
}

// ---- Channel create/edit bottom sheet ----

class _ChannelEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? channel;
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
      _nameController.text = ch['name'] as String? ?? '';
      _descriptionController.text = ch['description'] as String? ?? '';
      _colorController.text = ch['color'] as String? ?? '#000000';
      _isSensitive = ch['isSensitive'] as bool? ?? false;
      _allowRenoteToExternal = ch['allowRenoteToExternal'] as bool? ?? true;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u30c1\u30e3\u30f3\u30cd\u30eb\u540d\u3092\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044',
          ),
        ),
      );
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
          channelId: widget.channel!['id'] as String,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u4fdd\u5b58\u306b\u5931\u6557\u3057\u307e\u3057\u305f: $e',
            ),
          ),
        );
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
