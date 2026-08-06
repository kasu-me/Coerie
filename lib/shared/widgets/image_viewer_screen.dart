import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/cache_service.dart';
import '../../data/models/drive_file_model.dart';
import '../utils/download_helper.dart';

/// 画像のフルスクリーンビューア（拡大縮小・ダウンロード対応）。
///
/// note_card.dart の `_FullscreenImageViewer`（複数枚 PageView 対応）と
/// drive_screen.dart の `_DriveImagePreviewScreen`（1枚専用）がほぼ同一実装で
/// 重複していたため、この共通ウィジェットに統合した。1枚だけ表示したい場合は
/// [files] に要素1件のリストを渡す。
class ImageViewerScreen extends StatefulWidget {
  /// 表示するファイル。1枚だけ見せたい場合も要素1件のリストを渡す。
  final List<DriveFileModel> files;

  final int initialIndex;

  /// AppBar の見出し。表示の詳細は [_ImageViewerScreenState._titleText] を参照。
  final String? title;

  const ImageViewerScreen({
    super.key,
    required this.files,
    this.initialIndex = 0,
    this.title,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _current;
  late List<TransformationController> _controllers;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _controllers = List.generate(
      widget.files.length,
      (_) => TransformationController(),
    );
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          // アニメーション中は現在ページのコントローラーへ逐次反映する
          final anim = _animation;
          if (anim != null && _controllers.length > _current) {
            _controllers[_current].value = anim.value;
          }
        });
    if (_controllers.isNotEmpty) {
      _controllers[_current].addListener(_onTransformChanged);
    }
  }

  /// AppBar の見出し文字列。統合前の3画面それぞれの表示をそのまま再現する。
  ///
  /// | [ImageViewerScreen.title] | 枚数 | 表示 | 由来 |
  /// |---|---|---|---|
  /// | あり | 複数 | `タイトル (2/5)` | ギャラリー |
  /// | あり | 1枚 | `タイトル` | ドライブ |
  /// | なし | 複数 | `2 / 5` | ノート添付 |
  /// | なし | 1枚 | 見出しなし | ノート添付 |
  String? get _titleText {
    final title = widget.title;
    final total = widget.files.length;
    if (title == null) return total > 1 ? '${_current + 1} / $total' : null;
    return total > 1 ? '$title (${_current + 1}/$total)' : title;
  }

  void _onTransformChanged() {
    final scale = _controllers[_current].value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupBg = theme.colorScheme.surface;
    final popupOn = theme.colorScheme.onSurface;
    final files = widget.files;
    final titleText = _titleText;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: titleText == null
            ? null
            : Text(
                titleText,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          PopupMenuButton<String>(
            color: popupBg,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 8,
            offset: const Offset(0, 8),
            onSelected: (v) {
              if (v == 'download') {
                final file = files[_current];
                downloadWithFeedback(
                  context,
                  url: file.url,
                  fileName: file.name,
                );
              }
              if (v == 'open') {
                launchUrl(
                  Uri.parse(files[_current].url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ダウンロード',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ブラウザで開く',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: PageView.builder(
          controller: _pageController,
          physics: _isZoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: files.length,
          onPageChanged: (i) {
            _controllers[_current].removeListener(_onTransformChanged);
            setState(() {
              _current = i;
              _isZoomed = false;
            });
            _controllers[i].addListener(_onTransformChanged);
          },
          itemBuilder: (_, i) => GestureDetector(
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: () => _handleDoubleTap(i),
            child: InteractiveViewer(
              transformationController: _controllers[i],
              minScale: 0.5,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(48),
              child: Center(
                child: CachedNetworkImage(
                  cacheManager: AppCacheManager(),
                  imageUrl: files[i].url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) =>
                      const CircularProgressIndicator(color: Colors.white),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleDoubleTap(int index) {
    if (index < 0 || index >= _controllers.length) return;
    final controller = _controllers[index];
    final currentScale = controller.value.getMaxScaleOnAxis();
    final double targetScale = currentScale > 1.0 ? 1.0 : 2.5;
    final begin = controller.value;

    // フォーカルポイント: ダブルタップした位置（ウィジェットのローカル座標系）
    final focal = _doubleTapDetails?.localPosition ?? Offset.zero;

    // タップした位置が指の下に留まるように平行移動量を計算する
    final tx = -focal.dx * (targetScale - 1);
    final ty = -focal.dy * (targetScale - 1);

    final end = Matrix4.identity()..translateByDouble(tx, ty, 0.0, 1.0);
    end.multiply(Matrix4.diagonal3Values(targetScale, targetScale, 1.0));

    _animation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward(from: 0);

    _doubleTapDetails = null;
  }

  @override
  void dispose() {
    if (_controllers.isNotEmpty && _current < _controllers.length) {
      _controllers[_current].removeListener(_onTransformChanged);
    }
    _pageController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }
}
