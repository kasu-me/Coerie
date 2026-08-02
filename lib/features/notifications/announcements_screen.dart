import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/announcement_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/announcements_badge_provider.dart';
import '../../shared/widgets/mfm_content.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/providers/paged_notifier.dart';

// Provider
final _announcementsProvider = StateNotifierProvider.autoDispose
    .family<_AnnouncementsNotifier, PagedState<AnnouncementModel>, String>(
      (ref, accountId) => _AnnouncementsNotifier(ref),
    );

class _AnnouncementsNotifier extends PagedNotifier<AnnouncementModel> {
  final Ref _ref;

  _AnnouncementsNotifier(this._ref) {
    fetch();
  }

  @override
  String cursorOf(AnnouncementModel item) => item.id;

  @override
  Future<List<AnnouncementModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    return api.getAnnouncements(untilId: untilId);
  }

  /// ローカルで既読にしたフラグを再取得後も引き継ぐ。
  @override
  List<AnnouncementModel> mergeItems(List<AnnouncementModel> fetched) {
    final locallyMarked = state.items
        .where((e) => e.isRead)
        .map((e) => e.id)
        .toSet();
    return fetched
        .map(
          (f) => f.copyWith(isRead: f.isRead || locallyMarked.contains(f.id)),
        )
        .toList();
  }

  /// キャッシュ済みの一覧で該当のお知らせを既読にする。
  void markReadLocally(String announcementId) {
    state = state.copyWith(
      items: state.items
          .map(
            (a) => a.id == announcementId && !a.isRead
                ? a.copyWith(isRead: true)
                : a,
          )
          .toList(),
    );
  }
}

// Screen
class AnnouncementsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const AnnouncementsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      final accountId = ref.read(activeAccountProvider)?.id ?? '';
      ref
          .read(_announcementsProvider(accountId).notifier)
          .fetch(loadMore: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountId = ref.watch(activeAccountProvider)?.id ?? '';
    final state = ref.watch(_announcementsProvider(accountId));

    // Do not auto-clear announcements on open. Individual announcements
    // are marked read by user action in the detail screen.

    if (widget.embedded) {
      return _buildBody(context, state, accountId);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(_announcementsProvider(accountId).notifier).refresh(),
          ),
        ],
      ),
      body: _buildBody(context, state, accountId),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PagedState<AnnouncementModel> state,
    String accountId,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('読み込みに失敗しました', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref
                  .read(_announcementsProvider(accountId).notifier)
                  .refresh(),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('お知らせはありません'));
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(_announcementsProvider(accountId).notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          final a = state.items[index];
          return ListTile(
            title: Text(
              a.title ?? (a.text ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.text != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0, bottom: 6.0),
                    child: MfmContent(
                      text: a.text!,
                      enableAnimations: false,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(
                  formatRelativeTime(a.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
            trailing: a.isRead
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            onTap: () => context.push('/announcement/${a.id}', extra: a),
          );
        },
      ),
    );
  }
}

// Detail screen
class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  final AnnouncementModel announcement;
  const AnnouncementDetailScreen({super.key, required this.announcement});

  @override
  ConsumerState<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState
    extends ConsumerState<AnnouncementDetailScreen> {
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    // Do not auto-mark as read on open; marking is done by user action.
  }

  Future<void> _markRead() async {
    if (_marked) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    try {
      await api.readAnnouncement(widget.announcement.id);
      _marked = true;
      // Mark the item read locally so the list updates immediately, and
      // decrement the badge count locally.
      try {
        ref
            .read(_announcementsProvider(accountId).notifier)
            .markReadLocally(widget.announcement.id);
      } catch (_) {}
      try {
        ref
            .read(announcementsBadgeProvider(accountId).notifier)
            .markOneRead(widget.announcement.id);
      } catch (_) {}

      // Also try to refresh server state when possible.
      try {
        await ref
            .read(announcementsBadgeProvider(accountId).notifier)
            .refreshFromApi();
      } catch (_) {}
      try {
        await ref.read(_announcementsProvider(accountId).notifier).refresh();
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '既読にする',
            onPressed: () async {
              await _markRead();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('既読にしました')));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.title != null)
              Text(
                a.title!,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            Text(
              formatRelativeTime(a.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (a.text != null)
              MfmContent(text: a.text!, enableAnimations: true),
            if (a.url != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  final uri = Uri.tryParse(a.url!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('詳細を見る'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
