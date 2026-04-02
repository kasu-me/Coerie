import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timeline_provider.dart';
import 'widgets/note_card.dart';
import '../../core/streaming/streaming_service.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/widgets/scroll_to_top_fab.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeStream());
  }

  void _subscribeStream() {
    final streaming = ref.read(streamingServiceProvider);
    if (streaming == null) return;

    _streamSub?.cancel();
    _streamSub = streaming.subscribeTimeline(widget.timelineType)?.listen((
      note,
    ) {
      if (!mounted) return;
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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
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

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
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
        onRefresh: () =>
            ref.read(timelineProvider(widget.timelineType).notifier).refresh(),
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
            return NoteCard(note: state.notes[index]);
          },
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
          bottom: 16,
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
