import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/streaming/streaming_service.dart';
import '../../data/models/app_settings_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/notifications_badge_provider.dart';
import '../../shared/providers/notifications_tab_visibility_provider.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/home_drawer.dart';
import '../timeline/timeline_screen.dart';
import '../timeline/timeline_provider.dart';
import '../notifications/notification_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  TabController? _tabController;
  int _tabCount = 0;
  int? _lastTabIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    final tabs = ref.read(accountTabsProvider(accountId));
    _syncTabController(tabs.length);
  }

  void _syncTabController(int newCount) {
    if (newCount != _tabCount) {
      final prevIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabCount = newCount;
      if (newCount > 0) {
        _tabController = TabController(
          length: newCount,
          vsync: this,
          // 前のインデックスが範囲外の場合は0に戻す
          initialIndex: prevIndex < newCount ? prevIndex : 0,
        );
        _lastTabIndex = _tabController?.index;
        _tabController?.addListener(() {
          // Wait until animation settled
          if (_tabController == null) return;
          if (_tabController!.indexIsChanging) return;
          final idx = _tabController!.index;
          if (_lastTabIndex == idx) return;
          _lastTabIndex = idx;
          _handleTabChanged(idx);
        });
        // 初期表示時の可視フラグ設定
        final accountId = ref.read(activeAccountProvider)?.id ?? '';
        final tabs = ref.read(accountTabsProvider(accountId));
        final currentIdx = _tabController!.index;
        final isNotificationsTab =
            currentIdx >= 0 &&
            currentIdx < tabs.length &&
            tabs[currentIdx].type == AppConstants.tabTypeNotifications;
        ref.read(notificationsTabVisibilityProvider(accountId).notifier).state =
            isNotificationsTab;
      } else {
        _tabController = null;
      }
    }
  }

  void _handleTabChanged(int newIndex) {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    final tabs = ref.read(accountTabsProvider(accountId));
    if (newIndex < 0 || newIndex >= tabs.length) return;
    final tab = tabs[newIndex];
    // 通知タブの表示状態を更新する
    final isNotifications = tab.type == AppConstants.tabTypeNotifications;
    ref.read(notificationsTabVisibilityProvider(accountId).notifier).state =
        isNotifications;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider); // theme/fontSize等の変更を受け取る
    final accountId = ref.watch(activeAccountProvider)?.id ?? '';
    final tabs = ref.watch(accountTabsProvider(accountId));

    // タブ数変化を同フレームで即座に同期する（次フレームへの遅延を避ける）
    if (tabs.length != _tabCount) {
      _syncTabController(tabs.length);
    }
    // WebSocket 接続状態を監視：サーバーダウン時にバナー表示
    ref.listen<AsyncValue<StreamingStatus>>(streamingStatusProvider, (
      prev,
      next,
    ) {
      next.whenData((status) {
        final messenger = ScaffoldMessenger.of(context);
        if (status == StreamingStatus.serverDown) {
          messenger.hideCurrentMaterialBanner();
          messenger.showMaterialBanner(
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              content: const Text('サーバーに接続できません。リアルタイム更新が停止しています。'),
              leading: const Icon(Icons.wifi_off, color: Colors.white),
              backgroundColor: Theme.of(context).colorScheme.error,
              contentTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onError,
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    ref.read(streamingServiceProvider)?.retryConnect();
                    final account = ref.read(activeAccountProvider);
                    if (account != null) {
                      try {
                        await ref
                            .read(
                              notificationsBadgeProvider(account.id).notifier,
                            )
                            .refreshFromApi();
                      } catch (_) {}
                    }
                  },
                  child: Text(
                    '再接続',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else if (status == StreamingStatus.reconnecting) {
          // 再接続中はバナーを一旦閉じる（二重表示防止）
          messenger.hideCurrentMaterialBanner();
        } else if (status == StreamingStatus.connected) {
          // 再接続に成功したらバナーを閉じる
          messenger.hideCurrentMaterialBanner();
        }
      });
    });
    return Scaffold(
      key: _scaffoldKey,
      appBar: HomeAppBar(scaffoldKey: _scaffoldKey),
      drawer: const HomeDrawer(),
      body: tabs.isEmpty
          ? _EmptyTabsView()
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: tabs.length > 4,
                  tabs: tabs.map((t) {
                    if (t.type == AppConstants.tabTypeNotifications) {
                      final unread = ref.watch(
                        notificationsBadgeProvider(accountId),
                      );
                      return unread > 0
                          ? Tab(
                              child: Badge(
                                label: Text('$unread'),
                                child: Text(t.label),
                              ),
                            )
                          : Tab(text: t.label);
                    }
                    return Tab(text: t.label);
                  }).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const ClampingScrollPhysics(),
                    children: tabs
                        .map(
                          (t) => t.type == AppConstants.tabTypeNotifications
                              ? const NotificationScreen(embedded: true)
                              : TimelineScreen(
                                  // アカウントIDをKeyに含めることで、アカウント切り替え時に
                                  // ウィジェットを強制的に再作成して古いデータを即座にクリアする
                                  key: ValueKey(
                                    '$accountId:${_timelineKey(t)}',
                                  ),
                                  timelineType: _timelineKey(t),
                                ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/compose');
          // 投稿後にタイムラインを全タブでリフレッシュ
          if (mounted) {
            final currentAccountId = ref.read(activeAccountProvider)?.id ?? '';
            for (final tab in ref.read(accountTabsProvider(currentAccountId))) {
              if (tab.type != AppConstants.tabTypeNotifications) {
                ref
                    .read(timelineProvider(_timelineKey(tab)).notifier)
                    .refresh();
              }
            }
          }
        },
        child: const Icon(Icons.create),
      ),
    );
  }

  /// リスト/アンテナタブは "list:id" / "antenna:id" 形式のキーを使う
  String _timelineKey(TabConfigModel tab) {
    if ((tab.type == AppConstants.tabTypeList ||
            tab.type == AppConstants.tabTypeAntenna) &&
        tab.sourceId != null) {
      return '${tab.type}:${tab.sourceId}';
    }
    return tab.type;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
}

class _EmptyTabsView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tab_unselected,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text('タブが追加されていません', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('設定からタブを追加してください', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.push('/settings/tabs'),
            icon: const Icon(Icons.add),
            label: const Text('タブを追加'),
          ),
        ],
      ),
    );
  }
}
