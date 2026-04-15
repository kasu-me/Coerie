import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/timeline_screen.dart';

class ChannelDetailScreen extends ConsumerStatefulWidget {
  final String channelId;
  final Map<String, dynamic>? initialData;

  const ChannelDetailScreen({
    super.key,
    required this.channelId,
    this.initialData,
  });

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _channel;
  bool _isLoading = false;
  String? _error;
  bool _isInHomeTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _channel = widget.initialData;
    _load();
    _checkIsInHomeTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await api.getChannel(widget.channelId);
      if (mounted) setState(() => _channel = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _channelName =>
      _channel?['name'] as String? ??
      widget.initialData?['name'] as String? ??
      'チャンネル';

  void _checkIsInHomeTab() {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    final tabs = ref.read(accountTabsProvider(accountId));
    if (mounted) {
      setState(() {
        _isInHomeTab = tabs.any(
          (t) =>
              t.type == AppConstants.tabTypeChannel &&
              t.sourceId == widget.channelId,
        );
      });
    }
  }

  Future<void> _toggleHomeTab() async {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    if (accountId.isEmpty) return;
    final currentTabs = List<TabConfigModel>.from(
      ref.read(accountTabsProvider(accountId)),
    );

    if (_isInHomeTab) {
      currentTabs.removeWhere(
        (t) =>
            t.type == AppConstants.tabTypeChannel &&
            t.sourceId == widget.channelId,
      );
      await ref
          .read(accountTabsProvider(accountId).notifier)
          .setTabs(currentTabs);
      if (mounted) {
        setState(() => _isInHomeTab = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ホームタブから削除しました')));
      }
    } else {
      final labelController = TextEditingController(text: _channelName);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ホームタブに追加'),
          content: TextField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'タブ名',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('追加'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final label = labelController.text.trim().isEmpty
          ? _channelName
          : labelController.text.trim();
      currentTabs.add(
        TabConfigModel(
          id: const Uuid().v4(),
          label: label,
          type: AppConstants.tabTypeChannel,
          sourceId: widget.channelId,
        ),
      );
      await ref
          .read(accountTabsProvider(accountId).notifier)
          .setTabs(currentTabs);
      if (mounted) {
        setState(() => _isInHomeTab = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「$label」タブを追加しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_channelName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle_tab') _toggleHomeTab();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle_tab',
                child: Row(
                  children: [
                    Icon(
                      _isInHomeTab
                          ? Icons.remove_from_queue
                          : Icons.add_to_queue,
                    ),
                    const SizedBox(width: 8),
                    Text(_isInHomeTab ? 'ホームタブから削除' : 'ホームタブに追加'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '情報'),
            Tab(text: 'タイムライン'),
          ],
        ),
      ),
      body: _isLoading && _channel == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _channel == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('再試行')),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _InfoTab(
                  channel: _channel ?? widget.initialData ?? {},
                  onUpdated: _load,
                ),
                _TimelineTab(channelId: widget.channelId),
              ],
            ),
    );
  }
}

// ---- 情報タブ ----

class _InfoTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> channel;
  final VoidCallback onUpdated;

  const _InfoTab({required this.channel, required this.onUpdated});

  @override
  ConsumerState<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends ConsumerState<_InfoTab> {
  bool _isActionLoading = false;

  bool get _isOwner {
    final myUserId = ref.read(activeAccountProvider)?.userId;
    final ownerId = widget.channel['userId'] as String?;
    return myUserId != null && myUserId == ownerId;
  }

  Future<void> _toggleFollow() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final channelId = widget.channel['id'] as String;
    final isFollowing = widget.channel['isFollowing'] as bool? ?? false;
    setState(() => _isActionLoading = true);
    try {
      if (isFollowing) {
        await api.unfollowChannel(channelId);
      } else {
        await api.followChannel(channelId);
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final channelId = widget.channel['id'] as String;
    final isFavorited = widget.channel['isFavorited'] as bool? ?? false;
    setState(() => _isActionLoading = true);
    try {
      if (isFavorited) {
        await api.unfavoriteChannel(channelId);
      } else {
        await api.favoriteChannel(channelId);
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ChannelInfoEditSheet(
        channel: widget.channel,
        onSaved: widget.onUpdated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final name = ch['name'] as String? ?? '';
    final description = ch['description'] as String?;
    final bannerUrl = ch['bannerUrl'] as String?;
    final color = ch['color'] as String? ?? '#888888';
    final usersCount = ch['usersCount'] as int? ?? 0;
    final notesCount = ch['notesCount'] as int? ?? 0;
    final isArchived = ch['isArchived'] as bool? ?? false;
    final isSensitive = ch['isSensitive'] as bool? ?? false;
    final allowRenoteToExternal = ch['allowRenoteToExternal'] as bool? ?? true;
    final isFollowing = ch['isFollowing'] as bool? ?? false;
    final isFavorited = ch['isFavorited'] as bool? ?? false;

    Color channelColor;
    try {
      final hex = color.replaceAll('#', '');
      channelColor = Color(
        int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16),
      );
    } catch (_) {
      channelColor = Theme.of(context).colorScheme.primary;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // バナー画像
          if (bannerUrl != null)
            CachedNetworkImage(
              imageUrl: bannerUrl,
              height: 160,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                height: 160,
                color: channelColor.withValues(alpha: 0.3),
              ),
            )
          else
            Container(
              height: 80,
              color: channelColor.withValues(alpha: 0.2),
              child: Icon(Icons.tv, size: 48, color: channelColor),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイトルとバッジ
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: channelColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (isArchived)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'アーカイブ済',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 統計
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$usersCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.article_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$notesCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isSensitive) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'センシティブ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                if (!allowRenoteToExternal) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.block,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '外部へのリノート不可',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                // 説明
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(description),
                ],
                const SizedBox(height: 16),
                // アクションボタン
                if (_isOwner)
                  FilledButton.tonal(
                    onPressed: _showEditSheet,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 8),
                        Text('チャンネルを編集'),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _isActionLoading ? null : _toggleFollow,
                        style: isFollowing
                            ? FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.secondary,
                              )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isFollowing
                                  ? Icons.remove_circle_outline
                                  : Icons.add_circle_outline,
                            ),
                            const SizedBox(width: 8),
                            Text(isFollowing ? 'フォロー解除' : 'フォロー'),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _isActionLoading ? null : _toggleFavorite,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isFavorited ? Icons.star : Icons.star_outline),
                            const SizedBox(width: 8),
                            Text(isFavorited ? 'お気に入り解除' : 'お気に入りに追加'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 情報編集ボトムシート（オーナー用）----

class _ChannelInfoEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> channel;
  final VoidCallback onSaved;

  const _ChannelInfoEditSheet({required this.channel, required this.onSaved});

  @override
  ConsumerState<_ChannelInfoEditSheet> createState() =>
      _ChannelInfoEditSheetState();
}

class _ChannelInfoEditSheetState extends ConsumerState<_ChannelInfoEditSheet> {
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
    _nameController.text = ch['name'] as String? ?? '';
    _descriptionController.text = ch['description'] as String? ?? '';
    _colorController.text = ch['color'] as String? ?? '#000000';
    _isSensitive = ch['isSensitive'] as bool? ?? false;
    _allowRenoteToExternal = ch['allowRenoteToExternal'] as bool? ?? true;
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
      await api.updateChannel(
        channelId: widget.channel['id'] as String,
        name: name,
        description: _descriptionController.text.trim(),
        color: _colorController.text.trim().isEmpty
            ? '#000000'
            : _colorController.text.trim(),
        isSensitive: _isSensitive,
        allowRenoteToExternal: _allowRenoteToExternal,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('チャンネルを編集', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'チャンネル名 *',
              border: OutlineInputBorder(),
            ),
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- タイムラインタブ ----

class _TimelineTab extends ConsumerStatefulWidget {
  final String channelId;

  const _TimelineTab({required this.channelId});

  @override
  ConsumerState<_TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends ConsumerState<_TimelineTab> {
  @override
  Widget build(BuildContext context) {
    return TimelineScreen(timelineType: 'channel:${widget.channelId}');
  }
}
