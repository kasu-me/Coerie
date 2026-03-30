import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timeline_provider.dart';
import 'widgets/note_card.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  final String timelineType;

  const TimelineScreen({super.key, required this.timelineType});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

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
      ref
          .read(timelineProvider(widget.timelineType).notifier)
          .fetchNotes(loadMore: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

    if (state.notes.isEmpty) {
      return RefreshIndicator(
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
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(timelineProvider(widget.timelineType).notifier).fetchNotes(),
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
