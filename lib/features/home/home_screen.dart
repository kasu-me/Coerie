import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/providers/settings_provider.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/home_drawer.dart';
import '../timeline/timeline_screen.dart';
import '../notifications/notification_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  TabController? _tabController;
  int _tabCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = ref.read(settingsProvider).tabs;
    _syncTabController(tabs.length);
  }

  void _syncTabController(int newCount) {
    if (newCount != _tabCount) {
      _tabController?.dispose();
      _tabCount = newCount;
      _tabController = newCount > 0
          ? TabController(length: newCount, vsync: this)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final tabs = settings.tabs;

    // タブ数変化を次フレームで反映
    if (tabs.length != _tabCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _syncTabController(tabs.length));
      });
    }

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
                  tabs: tabs.map((t) => Tab(text: t.label)).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: tabs
                        .map(
                          (t) => t.type == AppConstants.tabTypeNotifications
                              ? const NotificationScreen(embedded: true)
                              : TimelineScreen(timelineType: t.type),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/compose'),
        child: const Icon(Icons.create),
      ),
    );
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
