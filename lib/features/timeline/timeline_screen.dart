import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timeline_provider.dart';
import 'widgets/note_card.dart';
import '../../core/streaming/streaming_service.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings_model.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  final String timelineType;

  const TimelineScreen({super.key, required this.timelineType});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  StreamSubscription? _streamSub;
  int _newNotesCount = 0;
  bool _wasReconnecting = false;
  bool _sourceMissing = false;
  bool _checkedSourceExists = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeStream());
  }

  @override
  void didUpdateWidget(TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timelineType != widget.timelineType) {
      _streamSub?.cancel();
      _streamSub = null;
      setState(() {
        _newNotesCount = 0;
        _checkedSourceExists = false;
        _sourceMissing = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _subscribeStream();
      });
    }
  }

  Future<void> _checkSourceExists() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final t = widget.timelineType;
    try {
      if (t.startsWith('list:')) {
        final id = t.substring(5);
        final lists = await api.getLists();
        final exists = lists.any((l) => (l['id'] as String?) == id);
        if (mounted) setState(() => _sourceMissing = !exists);
      } else if (t.startsWith('antenna:')) {
        final id = t.substring(8);
        final ants = await api.getAntennas();
        final exists = ants.any((a) => (a['id'] as String?) == id);
        if (mounted) setState(() => _sourceMissing = !exists);
      } else if (t.startsWith('channel:')) {
        final id = t.substring(8);
        try {
          await api.getChannel(id);
        } catch (_) {
          if (mounted) setState(() => _sourceMissing = true);
        }
      }
    } catch (_) {
      // ignore errors; do not mark as missing on API failures
    }
  }

  Future<void> _removeTabFromHome() async {
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    if (accountId.isEmpty) return;
    final tabs = List<TabConfigModel>.from(
      ref.read(accountTabsProvider(accountId)),
    );
    final t = widget.timelineType;
    final isList = t.startsWith('list:');
    final isAntenna = t.startsWith('antenna:');
    final isChannel = t.startsWith('channel:');
    final idToMatch = isList
        ? t.substring(5)
        : isAntenna
        ? t.substring(8)
        : isChannel
        ? t.substring(8)
        : null;
    if (idToMatch == null) return;
    final tabType = isList
        ? AppConstants.tabTypeList
        : isAntenna
        ? AppConstants.tabTypeAntenna
        : AppConstants.tabTypeChannel;
    final idx = tabs.indexWhere(
      (tab) => tab.type == tabType && tab.sourceId == idToMatch,
    );
    if (idx < 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('タブが見つかりませんでした')));
      }
      return;
    }
    tabs.removeAt(idx);
    await ref.read(accountTabsProvider(accountId).notifier).setTabs(tabs);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ホームタブから削除しました')));
  }

  void _subscribeStream() {
    final streaming = ref.read(streamingServiceProvider);
    if (streaming == null) return;

    _streamSub?.cancel();
    _streamSub = streaming.subscribeTimeline(widget.timelineType)?.listen((
      note,
    ) {
      if (!mounted) return;
      // ミュートユーザーの投稿はリアルタイムでも表示しない
      if (note.user.isMuted) return;
      // リノートの場合、リノート元の投稿者もミュートチェック
      if (note.renote != null && note.renote!.user.isMuted) return;
      // スクロールが先頭付近なら即追加、それ以外はバッジで通知
      if (_scrollController.hasClients &&
          _scrollController.position.pixels < 100) {
        ref
            .read(timelineProvider(widget.timelineType).notifier)
            .prependNote(note);
      } else {
        setState(() => _newNotesCount++);
      }
    });
  }

  void _scrollToTopAndRefresh() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _newNotesCount = 0);
    ref.read(timelineProvider(widget.timelineType).notifier).refresh();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // 新着バッジがある状態でユーザーが先頭までスクロールしたら新着を取得してバッジを消す
    if (pos.pixels < 100 && _newNotesCount > 0) {
      ref.read(timelineProvider(widget.timelineType).notifier).fetchNew();
      setState(() => _newNotesCount = 0);
    }

    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref
          .read(timelineProvider(widget.timelineType).notifier)
          .fetchNotes(loadMore: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // アカウント切り替え時にUIをリセットする
    ref.listen(activeAccountProvider, (prev, next) {
      if (prev?.id != next?.id) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        setState(() => _newNotesCount = 0);
      }
    });

    // アカウント切り替え時にストリーミングサービスが変わるため再購読する
    ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _streamSub?.cancel();
      _streamSub = null;
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _subscribeStream();
        });
      }
    });

    // 再接続後にギャップ期間の投稿を補填する
    ref.listen<AsyncValue<StreamingStatus>>(streamingStatusProvider, (
      prev,
      next,
    ) {
      next.whenData((status) {
        if (status == StreamingStatus.reconnecting) {
          _wasReconnecting = true;
        } else if (status == StreamingStatus.connected && _wasReconnecting) {
          _wasReconnecting = false;
          ref.read(timelineProvider(widget.timelineType).notifier).fetchNew();
        }
      });
    });

    final state = ref.watch(timelineProvider(widget.timelineType));

    // list/antenna/channel タブについて、該当ソースが存在するかを一度だけ確認する
    if (!_checkedSourceExists &&
        (widget.timelineType.startsWith('list:') ||
            widget.timelineType.startsWith('antenna:') ||
            widget.timelineType.startsWith('channel:')) &&
        !state.isLoading) {
      _checkedSourceExists = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkSourceExists();
      });
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      // ソース削除判定が真なら専用の削除UIを優先表示
      if (_sourceMissing) {
        final isList = widget.timelineType.startsWith('list:');
        final isChannel = widget.timelineType.startsWith('channel:');
        final label = isList
            ? 'リスト'
            : isChannel
            ? 'チャンネル'
            : 'アンテナ';
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delete_outline, size: 64),
              const SizedBox(height: 12),
              Text(
                '$label は削除されました',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _removeTabFromHome,
                child: const Text('ホームから削除'),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(state.error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref
                  .read(timelineProvider(widget.timelineType).notifier)
                  .fetchNotes(),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    Widget list;
    if (state.notes.isEmpty) {
      list = RefreshIndicator(
        onRefresh: () => ref
            .read(timelineProvider(widget.timelineType).notifier)
            .fetchNotes(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    const Text('投稿がありません'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      list = RefreshIndicator(
        onRefresh: () {
          setState(() => _newNotesCount = 0);
          return ref
              .read(timelineProvider(widget.timelineType).notifier)
              .refresh();
        },
        child: ListView.builder(
          controller: _scrollController,
          itemCount: state.notes.length + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == state.notes.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return NoteCard(
              key: ValueKey(state.notes[index].id),
              note: state.notes[index],
            );
          },
        ),
      );
    }

    // ソースが削除されている場合は専用のメッセージと削除ボタンを表示
    if (_sourceMissing) {
      final isList = widget.timelineType.startsWith('list:');
      final isChannel = widget.timelineType.startsWith('channel:');
      final label = isList
          ? 'リスト'
          : isChannel
          ? 'チャンネル'
          : 'アンテナ';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline, size: 64),
            const SizedBox(height: 12),
            Text(
              '$label は削除されました',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _removeTabFromHome,
              child: const Text('ホームから削除'),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        list,
        if (_newNotesCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonal(
              onPressed: _scrollToTopAndRefresh,
              child: Text('$_newNotesCount件の新しい投稿'),
            ),
          ),
        Positioned(
          key: const ValueKey('timelineScrollToTopFab'),
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

  @override
  void dispose() {
    _streamSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
}
