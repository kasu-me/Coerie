import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/streaming/streaming_service.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/notification_model.dart';
import '../profile/follow_requests_sheet.dart';
import '../../shared/providers/custom_emoji_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/notifications_badge_provider.dart';
import '../../shared/providers/notifications_tab_visibility_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/utils/emoji_utils.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/mixins/infinite_scroll_mixin.dart';
import '../../shared/providers/paged_notifier.dart';

// ---- Provider ----

final _notificationsProvider = StateNotifierProvider.autoDispose
    .family<_NotificationsNotifier, PagedState<NotificationModel>, String>(
      (ref, accountId) => _NotificationsNotifier(ref),
    );

class _NotificationsNotifier extends PagedNotifier<NotificationModel> {
  final Ref _ref;
  StreamSubscription<NotificationModel>? _streamSub;
  StreamSubscription<void>? _reconnectSub;

  _NotificationsNotifier(this._ref) {
    fetch();
    _subscribeStream();
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _streamSub?.cancel();
      _streamSub = null;
      _reconnectSub?.cancel();
      _reconnectSub = null;
      _subscribeStream();
    });
  }

  void _subscribeStream() {
    final streaming = _ref.read(streamingServiceProvider);
    if (streaming == null) return;
    _streamSub = streaming.notificationStream.listen(_onRealtimeNotification);
    // 再接続時は切断中に届かなかった通知をまとめて取得する
    _reconnectSub = streaming.reconnectedStream.listen((_) => _fetchMissed());
  }

  void _onRealtimeNotification(NotificationModel notification) {
    if (state.items.any((n) => n.id == notification.id)) return;
    state = state.copyWith(items: [notification, ...state.items]);
  }

  /// 再接続後、現在の先頭より新しい通知を取得して欠落分を補完する。
  Future<void> _fetchMissed() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null || state.items.isEmpty) return;
    try {
      final sinceId = state.items.first.id;
      final items = await api.getNotifications(sinceId: sinceId);
      if (items.isEmpty) return;
      final existingIds = state.items.map((n) => n.id).toSet();
      final newItems = items.where((n) => !existingIds.contains(n.id)).toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      if (newItems.isNotEmpty) {
        state = state.copyWith(items: [...newItems, ...state.items]);
      }
    } catch (_) {
      // 取得失敗は無視（次の更新で補完される）
    }
  }

  @override
  String cursorOf(NotificationModel item) => item.id;

  @override
  Future<List<NotificationModel>> fetchPage({String? untilId}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return [];
    return api.getNotifications(untilId: untilId);
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _reconnectSub?.cancel();
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
    with
        AutomaticKeepAliveClientMixin,
        InfiniteScrollMixin<NotificationScreen> {
  @override
  bool get wantKeepAlive => true;

  @override
  void onLoadMore() {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    ref.read(_notificationsProvider(accountId).notifier).fetch(loadMore: true);
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
              child: ScrollToTopFab(scrollController: scrollController),
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
              child: ScrollToTopFab(scrollController: scrollController),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PagedState<NotificationModel> state,
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
    // 接続先インスタンスのカスタム絵文字（マップは共有インスタンスをそのまま参照する）
    final instanceEmojis = ref.watch(customEmojiUrlMapProvider);

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(_notificationsProvider(accountId).notifier).refresh(),
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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
          final profileOwnerId = ref.read(activeAccountProvider)?.userId ?? '';
          return _NotificationTile(
            notification: state.items[index],
            emojiResolver: EmojiResolver(
              reactionEmojis: note?.reactionEmojis ?? const {},
              noteEmojis: note?.emojis ?? const {},
              instanceEmojis: instanceEmojis,
            ),
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
  final EmojiResolver emojiResolver;
  final String? profileOwnerId;

  const _NotificationTile({
    required this.notification,
    this.emojiResolver = EmojiResolver.empty,
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
                  UserAvatar(
                    avatarUrl: n.user?.avatarUrl,
                    radius: 22,
                    iconSize: 20,
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
                      // ユーザー名はある場合のみ表示。ない場合は
                      if (n.user?.name != null) {
                        spans.add(const TextSpan(style: TextStyle()));
                        spans.add(
                          TextSpan(
                            text: n.user?.name ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                        spans.add(
                          const TextSpan(text: ' ', style: TextStyle()),
                        );
                      }
                      spans.add(TextSpan(text: _typeLabel(n.type)));

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
                          imageUrl = emojiResolver.resolve(inner);
                        }

                        if (imageUrl != null) {
                          spans.add(
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: CachedNetworkImage(
                                  cacheManager: AppCacheManager(),
                                  imageUrl: imageUrl,
                                  height: 16,
                                  width: 16,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, _, _) => Text(
                                    ' $reactionKey',
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else if (inner == null) {
                          // Unicode絵文字は Twemoji CDN を使って画像化
                          final url = twemojiUrl(reactionKey);
                          spans.add(
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: CachedNetworkImage(
                                  cacheManager: AppCacheManager(),
                                  imageUrl: url,
                                  height: 16,
                                  width: 16,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, _, _) => Text(
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
                              text: ' $reactionKey',
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
                  if (n.note != null &&
                      n.note!.files.any((f) => f.isImage)) ...[
                    const SizedBox(height: 6),
                    _buildImagePreviews(context, n.note!.files),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    formatRelativeTime(n.createdAt),
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

  Widget _buildImagePreviews(BuildContext context, List<DriveFileModel> files) {
    final imageFiles = files.where((f) => f.isImage).take(4).toList();
    if (imageFiles.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < imageFiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                if (notification.note != null) {
                  context.push(
                    '/note/${notification.note!.id}',
                    extra: notification.note,
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: imageFiles[i].isSensitive
                      ? ColoredBox(
                          color: Colors.grey.shade800,
                          child: const Center(
                            child: Icon(
                              Icons.visibility_off,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          cacheManager: AppCacheManager(),
                          imageUrl:
                              imageFiles[i].thumbnailUrl ?? imageFiles[i].url,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => ColoredBox(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image, size: 24),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
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
    'login' => 'ログインがありました',
    'createToken' => 'アクセストークンが作成されました',
    'exportCompleted' => 'ノートのエクスポートが完了しました',
    'chatRoomInvitationReceived' => 'ダイレクトメッセージのグループへ招待されました',
    _ => type,
  };

  static IconData _typeIcon(String type) => switch (type) {
    'follow' ||
    'followRequestAccepted' ||
    'receiveFollowRequest' => Icons.person_add,
    'mention' || 'reply' => Icons.reply,
    'renote' || 'quote' => Icons.repeat,
    'reaction' => Icons.add_reaction_outlined,
    'login' => Icons.login,
    'createToken' => Icons.vpn_key,
    'exportCompleted' => Icons.file_download_done,
    _ => Icons.notifications_outlined,
  };

  static Color _typeColor(String type, ThemeData theme) => switch (type) {
    'follow' || 'followRequestAccepted' => Colors.green,
    'reaction' => Colors.orange,
    'renote' || 'quote' => theme.colorScheme.tertiary,
    _ => theme.colorScheme.primary,
  };
}
