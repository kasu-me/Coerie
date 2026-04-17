import 'package:flutter/material.dart';

/// スクロール位置が一定以上のときに表示される「トップへ戻る」ボタン。
/// [scrollController] を監視して [showThreshold] を超えたら表示する。
class ScrollToTopFab extends StatefulWidget {
  final ScrollController scrollController;
  final double showThreshold;

  const ScrollToTopFab({
    super.key,
    required this.scrollController,
    this.showThreshold = 400,
  });

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final pixels = widget.scrollController.position.pixels;
    final shouldShow = pixels > widget.showThreshold;
    if (shouldShow != _show) {
      setState(() => _show = shouldShow);
    }
  }

  void _scrollToTop() {
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_show,
        child: Tooltip(
          preferBelow: false,
          message: 'トップへ戻る',
          child: FloatingActionButton.small(
            heroTag: 'scrollToTop_${widget.scrollController.hashCode}',
            onPressed: _scrollToTop,
            child: const Icon(Icons.keyboard_arrow_up),
          ),
        ),
      ),
    );
  }
}
