import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/streaming/streaming_service.dart';
import '../../data/models/notification_model.dart';
import '../compose/emoji_picker_sheet.dart';
import '../profile/follow_requests_sheet.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/notifications_badge_provider.dart';
import '../../shared/providers/notifications_tab_visibility_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';

// ---- Provider ----

final _notificationsProvider = StateNotifierProvider.autoDispose
    .family<_NotificationsNotifier, _NotificationsState, String>(
      (ref, accountId) => _NotificationsNotifier(ref),
    );

class _NotificationsState {
  final List<NotificationModel> items;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const _NotificationsState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  _NotificationsState copyWith({
    List<NotificationModel>? items,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) => _NotificationsState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: error,
  );
}

class _NotificationsNotifier extends StateNotifier<_NotificationsState> {
  final Ref _ref;
  StreamSubscription<NotificationModel>? _streamSub;

  _NotificationsNotifier(this._ref) : super(const _NotificationsState()) {
    fetch();
    _subscribeStream();
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _streamSub?.cancel();
      _streamSub = null;
      _subscribeStream();
    });
  }

  void _subscribeStream() {
    final streaming = _ref.read(streamingServiceProvider);
    if (streaming == null) return;
    _streamSub = streaming.notificationStream.listen(_onRealtimeNotification);
  }

  void _onRealtimeNotification(NotificationModel notification) {
    if (state.items.any((n) => n.id == notification.id)) return;
    state = state.copyWith(items: [notification, ...state.items]);
  }

  Future<void> fetch({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final untilId = loadMore && state.items.isNotEmpty
          ? state.items.last.id
          : null;
      final items = await api.getNotifications(untilId: untilId);
      state = state.copyWith(
        isLoading: false,
        items: loadMore ? [...state.items, ...items] : items,
        hasMore: items.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    state = const _NotificationsState();
    await fetch();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}

// ---- Screen ----

class NotificationScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const NotificationScreen({super.key, this.embedded = false});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen>
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
          .read(_notificationsProvider(accountId).notifier)
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
    final state = ref.watch(_notificationsProvider(accountId));

    // タブ可視フラグと未読数を両方 watch することで、
    // タブ切替時や新着時に確実に rebuild されてバッジ消去処理が走る。
    final isVisible = ref.watch(notificationsTabVisibilityProvider(accountId));
    final unreadCount = ref.watch(notificationsBadgeProvider(accountId));

    // 通知タブが表示中 かつ 一番上の通知がレンダリングされていて 未読がある場合、
    // 次フレームで既読化してバッジを消す。
    if (isVisible && unreadCount > 0 && state.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final api = ref.read(misskeyApiProvider);
        await api?.markNotificationsRead().catchError((_) {});
        await ref.read(notificationsBadgeProvider(accountId).notifier).clear();
      });
    }

    if (widget.embedded) {
      return Stack(
        children: [
          _buildBody(context, state, accountId),
          Positioned(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: ScrollToTopFab(scrollController: _scrollController),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(_notificationsProvider(accountId).notifier).refresh(),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(context, state, accountId),
          Positioned(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: ScrollToTopFab(scrollController: _scrollController),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    _NotificationsState state,
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
                  .read(_notificationsProvider(accountId).notifier)
                  .refresh(),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('通知はありません'));
    }
    // カスタム絵文字のローカルマップを取得
    var localEmojiMap = <String, String>{};
    final customEmojisAsync = ref.watch(customEmojisProvider);
    customEmojisAsync.when(
      data: (list) {
        localEmojiMap = {
          for (final e in list)
            if (e['name'] != null && e['url'] != null)
              e['name'] as String: e['url'] as String,
        };
      },
      loading: () {},
      error: (_, __) {},
    );

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(_notificationsProvider(accountId).notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (context, i) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          final note = state.items[index].note;
          final emojiUrlMap = {
            ...localEmojiMap,
            if (note != null) ...note.emojis,
            if (note != null) ...note.reactionEmojis,
          };
          final profileOwnerId = ref.read(activeAccountProvider)?.userId ?? '';
          return _NotificationTile(
            notification: state.items[index],
            emojiUrlMap: emojiUrlMap,
            profileOwnerId: profileOwnerId,
          );
        },
      ),
    );
  }
}

// ---- Tile ----

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final Map<String, String> emojiUrlMap;
  final String? profileOwnerId;

  const _NotificationTile({
    required this.notification,
    this.emojiUrlMap = const {},
    this.profileOwnerId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = notification;

    return InkWell(
      onTap: () {
        const noteTypes = {'mention', 'reply', 'renote', 'quote', 'reaction'};
        if (n.note != null && noteTypes.contains(n.type)) {
          context.push('/note/${n.note!.id}', extra: n.note);
        } else if (n.type == 'receiveFollowRequest') {
          if (profileOwnerId != null && profileOwnerId!.isNotEmpty) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (ctx) =>
                  FollowRequestsSheet(profileOwnerId: profileOwnerId!),
            );
          } else if (n.user != null) {
            context.push('/profile/${n.user!.id}');
          }
        } else if (n.user != null) {
          context.push('/profile/${n.user!.id}');
        }
      },
      child: Container(
        color: n.isRead
            ? null
            : theme.colorScheme.primaryContainer.withAlpha(60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                if (n.user != null) {
                  context.push('/profile/${n.user!.id}');
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  n.user?.avatarUrl != null
                      ? CircleAvatar(
                          radius: 22,
                          backgroundImage: CachedNetworkImageProvider(
                            n.user!.avatarUrl!,
                          ),
                        )
                      : const CircleAvatar(
                          radius: 22,
                          child: Icon(Icons.person, size: 20),
                        ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: _typeColor(n.type, theme),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _typeIcon(n.type),
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ユーザー名 + 種別ラベル (+ リアクション絵文字は画像で表示)
                  Builder(
                    builder: (ctx) {
                      final spans = <InlineSpan>[];
                      spans.add(const TextSpan(style: TextStyle()));
                      spans.add(
                        TextSpan(
                          text: n.user?.name ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                      spans.add(TextSpan(text: ' ${_typeLabel(n.type)}'));

                      if (n.type == 'reaction' && n.reaction != null) {
                        final reactionKey = n.reaction!;
                        String? imageUrl;
                        // :name: 形式のカスタム絵文字を探す
                        String? inner;
                        if (reactionKey.startsWith(':') &&
                            reactionKey.endsWith(':')) {
                          inner = reactionKey.substring(
                            1,
                            reactionKey.length - 1,
                          );
                        }
                        if (inner != null) {
                          imageUrl = emojiUrlMap[inner];
                          if (imageUrl == null) {
                            final atIdx = inner.indexOf('@');
                            final nameOnly = atIdx >= 0
                                ? inner.substring(0, atIdx)
                                : inner;
                            imageUrl = emojiUrlMap[nameOnly];
                          }
                        }

                        if (imageUrl != null) {
                          spans.add(
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  height: 16,
                                  width: 16,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) => Text(
                                    ' $reactionKey',
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else if (inner == null) {
                          // Unicode絵文字は Twemoji CDN を使って画像化
                          final hex = reactionKey.runes
                              .map((r) => r.toRadixString(16))
                              .join('-');
                          final url =
                              'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$hex.png';
                          spans.add(
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: CachedNetworkImage(
                                  imageUrl: url,
                                  height: 16,
                                  width: 16,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) => Text(
                                    ' $reactionKey',
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else {
                          spans.add(
                            TextSpan(
                              text: ' ${reactionKey}',
                              style: const TextStyle(fontSize: 15),
                            ),
                          );
                        }
                      }

                      return RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: spans,
                        ),
                      );
                    },
                  ),
                  if (n.note?.text != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      n.note!.text!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(n.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'follow' => 'がフォローしました',
    'followRequestAccepted' => 'がフォローリクエストを承認しました',
    'mention' => 'があなたにメンションしました',
    'reply' => 'が返信しました',
    'renote' => 'がリノートしました',
    'quote' => 'が引用しました',
    'reaction' => 'がリアクションしました',
    'receiveFollowRequest' => 'がフォローリクエストを送りました',
    _ => type,
  };

  static IconData _typeIcon(String type) => switch (type) {
    'follow' ||
    'followRequestAccepted' ||
    'receiveFollowRequest' => Icons.person_add,
    'mention' || 'reply' => Icons.reply,
    'renote' || 'quote' => Icons.repeat,
    'reaction' => Icons.add_reaction_outlined,
    _ => Icons.notifications_outlined,
  };

  static Color _typeColor(String type, ThemeData theme) => switch (type) {
    'follow' || 'followRequestAccepted' => Colors.green,
    'reaction' => Colors.orange,
    'renote' || 'quote' => theme.colorScheme.tertiary,
    _ => theme.colorScheme.primary,
  };

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${dt.month}/${dt.day}';
  }
}
