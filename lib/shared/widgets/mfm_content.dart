import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mfm_parser/mfm_parser.dart' as mfm;
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../utils/emoji_utils.dart';
import '../utils/format_utils.dart';

/// MFM 中のリンクを開く。
///
/// クリップURL（`https://host/clips/<id>`）はアプリ内画面へ遷移させ、
/// それ以外は外部ブラウザで開く。
Future<void> openMfmUrl(BuildContext ctx, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'clips') {
    final clipId = uri.pathSegments[1];
    final host = uri.host;
    final query = host.isNotEmpty ? '?host=${Uri.encodeComponent(host)}' : '';
    ctx.push('/clips/$clipId$query');
    return;
  }

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// MFM (Markup language For Misskey) テキストをレンダリングするウィジェット。
///
/// [text] に MFM 記法を含む文字列を渡すと、太字・斜体・引用・コードブロック・
/// カスタム絵文字・URL リンクなどを適切に描画します。
class MfmContent extends StatefulWidget {
  final String text;
  final EmojiResolver emojiResolver;
  final TextStyle? style;
  final bool enableAnimations;
  final void Function(String username, String? host)? onMentionTap;

  /// 絵文字画像をテキストのベースラインに合わせるための下方向オフセット（フォントサイズ比）。
  static const double _emojiOffsetSizeY = 0.05;

  const MfmContent({
    super.key,
    required this.text,
    this.emojiResolver = EmojiResolver.empty,
    this.style,
    this.enableAnimations = false,
    this.onMentionTap,
  });

  @override
  State<MfmContent> createState() => _MfmContentState();

  // ---- パース結果キャッシュ ----

  /// パース済みノードツリーのキャッシュ（本文テキスト → ノード、パース失敗時は null）。
  ///
  /// [MfmContent] は再ビルドのたびに本文をパースし直すため、タイムラインの
  /// スクロールやリアクション操作で同じ本文のフルパースが何度も走る。
  /// 本文は不変なので内容をキーにキャッシュできる。
  /// 挿入順を保つ Map の性質を利用した簡易 LRU。
  static final Map<String, List<mfm.MfmNode>?> _nodeCache = {};
  static const int _nodeCacheLimit = 200;

  static List<mfm.MfmNode>? _parse(String text) {
    if (_nodeCache.containsKey(text)) {
      // 参照されたエントリを末尾へ移して、古いものから追い出されるようにする
      final cached = _nodeCache.remove(text);
      _nodeCache[text] = cached;
      return cached;
    }

    List<mfm.MfmNode>? nodes;
    try {
      nodes = const mfm.MfmParser().parse(text);
    } catch (_) {
      // パース失敗もキャッシュして、毎ビルドの再試行を避ける
      nodes = null;
    }

    if (_nodeCache.length >= _nodeCacheLimit) {
      _nodeCache.remove(_nodeCache.keys.first);
    }
    _nodeCache[text] = nodes;
    return nodes;
  }

  // ---- 静的ユーティリティ ----

  /// テキストを MFM パースして最初の URL を返す（OGP カード表示用）。
  static String? extractFirstUrl(String text) {
    final nodes = _parse(text);
    if (nodes == null) return null;
    return _findFirstUrl(nodes);
  }

  static String? _findFirstUrl(List<mfm.MfmNode> nodes) {
    for (final node in nodes) {
      if (node is mfm.MfmURL) return node.value;
      if (node is mfm.MfmLink) return node.url;
      if (node.children != null) {
        final found = _findFirstUrl(node.children!);
        if (found != null) return found;
      }
    }
    return null;
  }
}

class _MfmContentState extends State<MfmContent> {
  /// このビルドで生成した [TapGestureRecognizer]。
  ///
  /// TextSpan に渡した recognizer は明示的に破棄しないと解放されないため、
  /// ビルドごとに作り直したものを保持し、次のビルドと dispose で破棄する。
  List<TapGestureRecognizer> _recognizers = [];
  List<TapGestureRecognizer> _buildingRecognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// タップ処理付きの recognizer を生成し、破棄対象として登録する。
  TapGestureRecognizer _tapRecognizer(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _buildingRecognizers.add(recognizer);
    return recognizer;
  }

  // ---- インスタンスヘルパー ----

  Color? _parseHexColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      if (h.length == 6) {
        return Color(int.parse('FF$h', radix: 16));
      } else if (h.length == 3) {
        final r = h[0];
        final g = h[1];
        final b = h[2];
        return Color(int.parse('FF$r$r$g$g$b$b', radix: 16));
      }
    } catch (_) {}
    return null;
  }

  // ---- ノードツリー → Widget ----

  Widget _buildNodeList(
    List<mfm.MfmNode> nodes,
    TextStyle base,
    BuildContext ctx,
  ) {
    final segments = <Widget>[];
    final inlineBuf = <mfm.MfmNode>[];

    void flush() {
      if (inlineBuf.isEmpty) return;
      final spans = _buildSpans(inlineBuf, base, ctx);
      segments.add(
        RichText(
          text: TextSpan(style: base, children: spans),
        ),
      );
      inlineBuf.clear();
    }

    for (final node in nodes) {
      if (node is mfm.MfmBlock) {
        flush();
        segments.add(_buildBlockWidget(node, base, ctx));
      } else {
        inlineBuf.add(node);
      }
    }
    flush();

    if (segments.isEmpty) return const SizedBox.shrink();
    if (segments.length == 1) return segments.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments,
    );
  }

  Widget _buildBlockWidget(
    mfm.MfmBlock node,
    TextStyle base,
    BuildContext ctx,
  ) {
    final theme = Theme.of(ctx);

    if (node is mfm.MfmQuote) {
      final dimStyle = base.copyWith(
        color: (base.color ?? theme.colorScheme.onSurface).withValues(
          alpha: 0.65,
        ),
      );
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: _buildNodeList(node.children ?? [], dimStyle, ctx),
      );
    }

    if (node is mfm.MfmCodeBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            node.code,
            style: base.copyWith(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 14) * 0.9,
            ),
          ),
        ),
      );
    }

    if (node is mfm.MfmMathBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          node.formula,
          style: base.copyWith(fontFamily: 'monospace'),
        ),
      );
    }

    if (node is mfm.MfmCenter) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(child: _buildNodeList(node.children ?? [], base, ctx)),
      );
    }

    if (node is mfm.MfmSearch) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final uri = Uri.parse(
              'https://www.google.com/search?q=${Uri.encodeQueryComponent(node.query)}',
            );
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(child: Text(node.query, style: base)),
                const SizedBox(width: 8),
                Icon(Icons.search, color: theme.colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),
      );
    }

    // フォールバック: 子ノードをインラインとして描画
    return RichText(
      text: TextSpan(
        style: base,
        children: _buildSpans(node.children ?? [], base, ctx),
      ),
    );
  }

  // ---- ノードツリー → InlineSpan ----

  List<InlineSpan> _buildSpans(
    List<mfm.MfmNode> nodes,
    TextStyle style,
    BuildContext ctx,
  ) {
    final result = <InlineSpan>[];
    for (final node in nodes) {
      result.addAll(_nodeToSpans(node, style, ctx));
    }
    return result;
  }

  static const _maxUrlDisplayLength = 40;

  /// mfm_parser 1.0.6 の tweemoji regex でカバーされていない Unicode 17.0 の絵文字。
  /// ZWJ シーケンス（🧑‍🩰）は個別文字より先にマッチさせるため先頭に置く。
  /// ※ Dart の RegExp は非 Unicode モードのため文字クラス [...] 内では
  ///   サロゲートペアが分解されてしまう。| による個別のオルタネーションで記述する。
  static final _unicode17EmojiRegex = RegExp(
    '\u{1F9D1}\u200D\u{1FA70}' // 🧑‍🩰
    '|\u{1FA8A}' // 🪊
    '|\u{1FA8E}' // 🪎
    '|\u{1FAC8}' // 🫈
    '|\u{1FACD}' // 🫍
    '|\u{1FAEA}' // 🫪
    '|\u{1FAEF}' // 🫯
    '|\u{1F6D8}', // 🛘
  );

  List<InlineSpan> _nodeToSpans(
    mfm.MfmNode node,
    TextStyle style,
    BuildContext ctx,
  ) {
    final theme = Theme.of(ctx);

    if (node is mfm.MfmText) {
      return _buildTextWithUnicode17(node.text, style);
    }

    if (node is mfm.MfmBold) {
      return _buildSpans(
        node.children ?? [],
        style.copyWith(fontWeight: FontWeight.bold),
        ctx,
      );
    }

    if (node is mfm.MfmItalic) {
      return _buildSpans(
        node.children ?? [],
        style.copyWith(fontStyle: FontStyle.italic),
        ctx,
      );
    }

    if (node is mfm.MfmSmall) {
      return _buildSpans(
        node.children ?? [],
        style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.85,
          color: (style.color ?? theme.colorScheme.onSurface).withValues(
            alpha: 0.7,
          ),
        ),
        ctx,
      );
    }

    if (node is mfm.MfmStrike) {
      return _buildSpans(
        node.children ?? [],
        style.copyWith(decoration: TextDecoration.lineThrough),
        ctx,
      );
    }

    if (node is mfm.MfmInlineCode) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              node.code,
              style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 14) * 0.9,
              ),
            ),
          ),
        ),
      ];
    }

    if (node is mfm.MfmMathInline) {
      // 数式はプレーンテキストとして表示
      return [TextSpan(text: node.formula, style: style)];
    }

    if (node is mfm.MfmPlain) {
      return [
        TextSpan(text: _stripVariationSelectors(node.text), style: style),
      ];
    }

    if (node is mfm.MfmMention) {
      return [
        TextSpan(
          text: node.acct,
          style: style.copyWith(color: theme.colorScheme.primary),
          recognizer: _tapRecognizer(
            () => widget.onMentionTap?.call(node.username, node.host),
          ),
        ),
      ];
    }

    if (node is mfm.MfmHashTag) {
      return [
        TextSpan(
          text: '#${node.hashTag}',
          style: style.copyWith(color: theme.colorScheme.primary),
          recognizer: _tapRecognizer(
            () => ctx.push('/search', extra: {'tab': 1, 'query': node.hashTag}),
          ),
        ),
      ];
    }

    if (node is mfm.MfmURL) {
      final raw = node.value;
      final disp = raw.length > _maxUrlDisplayLength
          ? '${raw.substring(0, _maxUrlDisplayLength - 1)}…'
          : raw;
      final display = node.brackets == true ? '<$disp>' : disp;
      return [
        TextSpan(
          text: display,
          style: style.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
          recognizer: _tapRecognizer(() => openMfmUrl(ctx, raw)),
        ),
      ];
    }

    if (node is mfm.MfmLink) {
      // silent (= ?[text](url)) はリンクプレビューを非表示にするだけで
      // リンク自体はクリック可能なため、通常リンクと同じ処理を行う
      final childSpans = _buildSpans(node.children ?? [], style, ctx);
      return [
        TextSpan(
          children: childSpans,
          style: style.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
          recognizer: _tapRecognizer(() => openMfmUrl(ctx, node.url)),
        ),
      ];
    }

    if (node is mfm.MfmEmojiCode) {
      final url = widget.emojiResolver.resolve(node.name);
      final emojiSize = style.fontSize ?? 20.0;
      if (url != null) {
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.translate(
              offset: Offset(0, emojiSize * MfmContent._emojiOffsetSizeY),
              child: CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: url,
                height: emojiSize,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerLeft,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) =>
                    SizedBox(height: emojiSize, width: emojiSize * 0.9),
                errorWidget: (_, _, _) => Text(':${node.name}:', style: style),
              ),
            ),
          ),
        ];
      }
      return [TextSpan(text: ':${node.name}:', style: style)];
    }

    if (node is mfm.MfmUnicodeEmoji) {
      final emojiSize = style.fontSize ?? 20.0;
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Transform.translate(
            offset: Offset(0, emojiSize * MfmContent._emojiOffsetSizeY),
            child: CachedNetworkImage(
              cacheManager: AppCacheManager(),
              imageUrl: twemojiUrl(node.emoji),
              height: emojiSize,
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerLeft,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) =>
                  SizedBox(height: emojiSize, width: emojiSize * 0.9),
              errorWidget: (_, _, _) => Text(node.emoji, style: style),
            ),
          ),
        ),
      ];
    }

    if (node is mfm.MfmFn) {
      return _fnToSpans(node, style, ctx);
    }

    // ブロック要素がインライン文脈に来た場合は WidgetSpan でラップ
    if (node is mfm.MfmBlock) {
      return [WidgetSpan(child: _buildBlockWidget(node, style, ctx))];
    }

    // フォールバック: 子ノードを再帰処理
    if (node.children != null && node.children!.isNotEmpty) {
      return _buildSpans(node.children!, style, ctx);
    }

    return [];
  }

  List<InlineSpan> _fnToSpans(
    mfm.MfmFn node,
    TextStyle style,
    BuildContext ctx,
  ) {
    final children = node.children ?? [];
    final baseFontSize = style.fontSize ?? 14;

    switch (node.name) {
      // フォントサイズ拡大
      case 'x2':
        return _buildSpans(
          children,
          style.copyWith(fontSize: baseFontSize * 2.0),
          ctx,
        );
      case 'x3':
        return _buildSpans(
          children,
          style.copyWith(fontSize: baseFontSize * 3.0),
          ctx,
        );
      case 'x4':
        return _buildSpans(
          children,
          style.copyWith(fontSize: baseFontSize * 4.0),
          ctx,
        );

      // 前景色
      case 'fg':
        final colorStr = node.args['color']?.toString();
        final color = colorStr != null ? _parseHexColor(colorStr) : null;
        return _buildSpans(
          children,
          color != null ? style.copyWith(color: color) : style,
          ctx,
        );

      // 背景色
      case 'bg':
        final colorStr = node.args['color']?.toString();
        final color = colorStr != null ? _parseHexColor(colorStr) : null;
        if (color == null) return _buildSpans(children, style, ctx);
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              color: color,
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // ぼかし
      case 'blur':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // フォント指定
      case 'font':
        String? fontFamily;
        if (node.args.containsKey('serif')) fontFamily = 'serif';
        if (node.args.containsKey('monospace')) fontFamily = 'monospace';
        if (node.args.containsKey('cursive')) fontFamily = 'cursive';
        if (node.args.containsKey('fantasy')) fontFamily = 'fantasy';
        return _buildSpans(
          children,
          fontFamily != null ? style.copyWith(fontFamily: fontFamily) : style,
          ctx,
        );

      // 回転
      case 'rotate':
        // deg= 引数がない場合は Misskey 公式実装に合わせてデフォルト 90 度
        final deg = double.tryParse(node.args['deg']?.toString() ?? '') ?? 90.0;
        final rad = deg * (math.pi / 180);
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _RotateWidget(
              angle: rad,
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // 反転 ($[flip.v ...] or $[flip.h,v ...] or $[flip ...])
      case 'flip':
        final flipH = !node.args.containsKey('v') || node.args.containsKey('h');
        final flipV = node.args.containsKey('v');
        final sx = flipH ? -1.0 : 1.0;
        final sy = flipV ? -1.0 : 1.0;
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.scale(
              scaleX: sx,
              scaleY: sy,
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // 位置ずらし ($[position.x=0.8,y=0.5 ...])
      case 'position':
        final px = double.tryParse(node.args['x']?.toString() ?? '') ?? 0.0;
        final py = double.tryParse(node.args['y']?.toString() ?? '') ?? 0.0;
        final em = baseFontSize;
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.translate(
              offset: Offset(px * em, py * em),
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // 枠線 ($[border.style=solid,width=4 ...])
      case 'border':
        {
          final styleStr = node.args['style']?.toString() ?? 'solid';
          final colorStr = node.args['color']?.toString();
          final borderColor = colorStr != null
              ? _parseHexColor(colorStr)
              : null;
          final widthVal =
              double.tryParse(node.args['width']?.toString() ?? '') ?? 1.0;
          final radiusVal =
              double.tryParse(node.args['radius']?.toString() ?? '') ?? 0.0;
          // Flutter の Border が持つ線種は solid / none のみ。
          // dotted・dashed 等の CSS 線種は描画できないため solid で近似する。
          final bs = styleStr == 'hidden'
              ? BorderStyle.none
              : BorderStyle.solid;
          final effectiveBorderColor =
              borderColor ?? Theme.of(ctx).colorScheme.outline;
          return [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: effectiveBorderColor,
                    width: widthVal,
                    style: bs,
                  ),
                  borderRadius: radiusVal > 0
                      ? BorderRadius.circular(radiusVal)
                      : null,
                ),
                child: RichText(
                  text: TextSpan(
                    style: style,
                    children: _buildSpans(children, style, ctx),
                  ),
                ),
              ),
            ),
          ];
        }

      // UNIX時間 ($[unixtime 1701356400])
      case 'unixtime':
        {
          // 子ノードのテキストを結合して UNIX タイムスタンプを取得
          final raw = children
              .whereType<mfm.MfmText>()
              .map((t) => t.text.trim())
              .join();
          final ts = int.tryParse(raw);
          if (ts == null) return _buildSpans(children, style, ctx);
          final dt = DateTime.fromMillisecondsSinceEpoch(
            ts * 1000,
            isUtc: false,
          );
          return [TextSpan(text: formatYmdHms(dt), style: style)];
        }

      // スケール
      case 'scale':
        final x = double.tryParse(node.args['x']?.toString() ?? '') ?? 1.0;
        final y = double.tryParse(node.args['y']?.toString() ?? '') ?? 1.0;
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.scale(
              scaleX: x,
              scaleY: y,
              child: RichText(
                text: TextSpan(
                  style: style,
                  children: _buildSpans(children, style, ctx),
                ),
              ),
            ),
          ),
        ];

      // アニメーション系
      case 'jelly':
      case 'tada':
      case 'jump':
      case 'bounce':
      case 'spin':
      case 'shake':
      case 'twitch':
      case 'rainbow':
      case 'fall':
      case 'sparkle':
        if (!widget.enableAnimations) return _buildSpans(children, style, ctx);
        return _buildAnimationSpans(node.name, node.args, children, style, ctx);

      // 振り仮名 ($[ruby ベーステキスト ルビ])
      // 最後のスペースより前がベーステキスト、後がルビ読みになる
      case 'ruby':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _buildRubyWidget(children, style, ctx),
          ),
        ];

      // 未対応の関数名 → 子ノードをそのまま表示
      default:
        return _buildSpans(children, style, ctx);
    }
  }

  /// $[ruby] のルビウィジェットを構築する。
  ///
  /// 子ノードリストの末尾テキストを最後のスペースで分割し、
  /// 前半をベーステキスト、後半をルビ読みとして Column に積む。
  Widget _buildRubyWidget(
    List<mfm.MfmNode> children,
    TextStyle style,
    BuildContext ctx,
  ) {
    String rubyReading = '';
    List<mfm.MfmNode> baseChildren = List.from(children);

    if (children.isNotEmpty && children.last is mfm.MfmText) {
      final lastText = (children.last as mfm.MfmText).text;
      final lastSpace = lastText.lastIndexOf(' ');
      if (lastSpace >= 0) {
        rubyReading = lastText.substring(lastSpace + 1);
        final beforeText = lastText.substring(0, lastSpace);
        baseChildren = [
          ...children.take(children.length - 1),
          if (beforeText.isNotEmpty) mfm.MfmText(beforeText),
        ];
      } else {
        // スペースなし → テキスト全体をルビ読みとして扱い、ベースは前の子ノード
        rubyReading = lastText;
        baseChildren = children.take(children.length - 1).toList();
      }
    }

    final baseFontSize = style.fontSize ?? 14;
    // height: 1.0 でルビとベーステキストの行間を詰める
    final rubyStyle = style.copyWith(fontSize: baseFontSize * 0.5, height: 1.0);

    // ルビを Unicode コードポイント単位で分割（均等割り付け用）
    final rubyChars = rubyReading.runes.map(String.fromCharCode).toList();

    return _RubyBaselineWrapper(
      // IntrinsicWidth + stretch で Column の幅を最も広い子に合わせる。
      // ルビ < ベーステキスト → ルビ Row が引き伸ばされ均等割り付け。
      // ルビ > ベーステキスト → RichText が引き伸ばされ textAlign.center で中央配置。
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: rubyChars.length <= 1
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: rubyChars
                  .map((c) => Text(c, style: rubyStyle))
                  .toList(),
            ),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: style,
                children: _buildSpans(baseChildren, style, ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// MFM の speed 引数（例: "1.5s", "2s"）をミリ秒に変換する。
  /// 引数が null または無効な場合は null を返す（各ウィジェットのデフォルト値を使用する）。
  static int? _parseSpeedMs(dynamic speedArg) {
    if (speedArg == null) return null;
    var s = speedArg.toString().trim();
    if (s.endsWith('s')) s = s.substring(0, s.length - 1);
    final secs = double.tryParse(s);
    if (secs == null || secs <= 0) return null;
    return (secs * 1000).round();
  }

  List<InlineSpan> _buildAnimationSpans(
    String name,
    Map<String, dynamic> args,
    List<mfm.MfmNode> children,
    TextStyle style,
    BuildContext ctx,
  ) {
    final childWidget = RichText(
      text: TextSpan(style: style, children: _buildSpans(children, style, ctx)),
    );
    final durationMs = _parseSpeedMs(args['speed']);

    // 各エフェクトは「0→1 を繰り返す進捗 t から Transform 等を組む」形に
    // 統一できるため、共通の [_MfmAnimation] にビルダーだけを渡す。
    final Widget animated = switch (name) {
      'spin' => _MfmAnimation(
        durationMs: durationMs ?? 1500,
        // alternate 指定時は往復（0→1→0）させる
        reverse: args.containsKey('alternate'),
        builder: (t, child) => _spinTransform(
          t,
          alternate: args.containsKey('alternate'),
          axis: args.containsKey('x')
              ? _SpinAxis.x
              : args.containsKey('y')
              ? _SpinAxis.y
              : _SpinAxis.z,
          child: child,
        ),
        child: childWidget,
      ),
      'shake' => _MfmAnimation(
        durationMs: durationMs ?? 500,
        builder: (t, child) => Transform.translate(
          offset: Offset(3 * math.sin(t * 2 * math.pi * 3), 0),
          child: child,
        ),
        child: childWidget,
      ),
      'jump' => _MfmAnimation(
        durationMs: durationMs ?? 750,
        builder: (t, child) => Transform.translate(
          offset: Offset(0, -16 * math.sin(t * math.pi).clamp(0.0, 1.0)),
          child: child,
        ),
        child: childWidget,
      ),
      'fall' => _MfmAnimation(
        durationMs: durationMs ?? 2000,
        builder: (t, child) => Transform.translate(
          // 0→1 の Curved で加速しながら落下
          offset: Offset(0, 60 * Curves.easeIn.transform(t)),
          child: Opacity(opacity: (1.0 - t).clamp(0.0, 1.0), child: child),
        ),
        child: childWidget,
      ),
      'bounce' => _MfmAnimation(
        durationMs: durationMs ?? 500,
        builder: (t, child) => Transform.translate(
          offset: Offset(0, -12 * math.sin(t * math.pi)),
          child: child,
        ),
        child: childWidget,
      ),
      'jelly' || 'tada' => _MfmAnimation(
        durationMs: durationMs ?? 1000,
        builder: (t, child) => Transform.scale(
          scale: 1.0 + 0.15 * math.sin(t * 2 * math.pi),
          child: child,
        ),
        child: childWidget,
      ),
      'twitch' => _MfmAnimation(
        durationMs: durationMs ?? 200,
        builder: (t, child) => Transform.translate(
          offset: Offset(
            3 * math.sin(t * 2 * math.pi * 7),
            2 * math.sin(t * 2 * math.pi * 13),
          ),
          child: child,
        ),
        child: childWidget,
      ),
      'rainbow' => _MfmAnimation(
        durationMs: durationMs ?? 3000,
        builder: (t, child) => ColorFiltered(
          colorFilter: ColorFilter.matrix(_hueRotationMatrix(t * 360)),
          child: child,
        ),
        child: childWidget,
      ),
      'sparkle' => _SparkleWidget(child: childWidget),
      _ => childWidget,
    };

    return [
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: animated),
    ];
  }

  // ---- テキスト正規化 ----

  /// mfm_parser が認識しない Unicode 17.0 絵文字を含むテキストを、
  /// テキスト部分の [TextSpan] と絵文字部分の [WidgetSpan] に分割して返す。
  List<InlineSpan> _buildTextWithUnicode17(String text, TextStyle style) {
    final stripped = _stripVariationSelectors(text);
    if (!_unicode17EmojiRegex.hasMatch(stripped)) {
      return [TextSpan(text: stripped, style: style)];
    }
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in _unicode17EmojiRegex.allMatches(stripped)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: stripped.substring(lastEnd, match.start),
            style: style,
          ),
        );
      }
      final emoji = match.group(0)!;
      final emojiSize = style.fontSize ?? 20.0;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Transform.translate(
            offset: Offset(0, emojiSize * MfmContent._emojiOffsetSizeY),
            child: CachedNetworkImage(
              cacheManager: AppCacheManager(),
              imageUrl: twemojiUrl(emoji),
              height: emojiSize,
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerLeft,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) =>
                  SizedBox(height: emojiSize, width: emojiSize * 0.9),
              errorWidget: (_, _, _) => Text(emoji, style: style),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < stripped.length) {
      spans.add(TextSpan(text: stripped.substring(lastEnd), style: style));
    }
    return spans;
  }

  /// U+FE0F（絵文字表示セレクタ）・U+FE0E（テキスト表示セレクタ）を除去する。
  ///
  /// mfm_parser は U+FE0F を Twemoji regex で単体マッチし、ノードではなく
  /// 文字列として mergeText に流す。その結果 MfmText 内に U+FE0F が残存し、
  /// Flutter のフォントシェーピングが直前文字（例: ↓ U+2193）と組み合わせて
  /// 絵文字バリエーションシーケンスと解釈するケースがある。
  /// そうなると NotoColorEmoji 等の絵文字フォントで極端に大きく描画され
  /// 他の文字と大きさが揃わなくなるため、ここで除去する。
  static String _stripVariationSelectors(String text) {
    // U+FE0F: 絵文字表示セレクタ（Emoji Presentation）
    // U+FE0E: テキスト表示セレクタ（Text Presentation）
    return text.replaceAll('\uFE0F', '').replaceAll('\uFE0E', '');
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style;
    // テーマの bodyMedium を基底として明示的に fontFamily を引き継いだうえで、
    // 呼び出し元から渡された style でフォントサイズ等を上書きする。
    // RichText は DefaultTextStyle を継承しないため、ここで合成しないと
    // テーマ指定のフォント（Noto Sans JP 等）が適用されず、フォントメトリクスが
    // 不安定になり文字の大きさが揃わない問題が起きる。
    final base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .merge(style)
        .copyWith(color: style?.color ?? theme.colorScheme.onSurface);

    // 今回のビルドで作る recognizer を集める。前回ぶんはビルド完了後に破棄する。
    final previous = _recognizers;
    _buildingRecognizers = [];

    final nodes = MfmContent._parse(widget.text);
    final result = nodes == null
        // パースエラー時はプレーンテキストで表示
        ? RichText(
            text: TextSpan(text: widget.text, style: base),
          )
        : _buildNodeList(nodes, base, context);

    _recognizers = _buildingRecognizers;
    _buildingRecognizers = [];
    // 直前のフレームで表示中の span がまだ旧 recognizer を参照しているため、
    // 破棄はフレーム確定後まで遅らせる。
    if (previous.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in previous) {
          r.dispose();
        }
      });
    }

    return result;
  }
}

// ---- MFM アニメーションウィジェット ----

enum _SpinAxis { x, y, z }

/// 0→1 を繰り返す進捗 [t] から表示を組み立てる、MFM アニメーション共通の土台。
///
/// shake / jump / fall / bounce / jelly / twitch / rainbow / spin は
/// 「AnimationController を repeat して child を変形する」点が共通なので、
/// 差分となる変形だけを [builder] で受け取る。
class _MfmAnimation extends StatefulWidget {
  final Widget child;
  final int durationMs;

  /// true なら 0→1→0 と往復する（[AnimationController.repeat] の reverse）。
  final bool reverse;

  /// 進捗 t（0.0〜1.0）と child から表示するウィジェットを組み立てる。
  final Widget Function(double t, Widget child) builder;

  const _MfmAnimation({
    required this.child,
    required this.durationMs,
    required this.builder,
    this.reverse = false,
  });

  @override
  State<_MfmAnimation> createState() => _MfmAnimationState();
}

class _MfmAnimationState extends State<_MfmAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    )..repeat(reverse: widget.reverse);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      // child は再構築されないよう AnimatedBuilder に預ける
      builder: (_, child) => widget.builder(_ctrl.value, child!),
      child: widget.child,
    );
  }
}

/// $[spin] の回転変形。軸ごとに Matrix4 を組む。
Widget _spinTransform(
  double t, {
  required bool alternate,
  required _SpinAxis axis,
  required Widget child,
}) {
  // alternate 時は往復再生と組み合わせて -90°〜+90° を行き来する
  final angle = alternate ? (t - 0.5) * math.pi : t * 2 * math.pi;
  if (axis == _SpinAxis.z) {
    return Transform.rotate(angle: angle, child: child);
  }
  final matrix = Matrix4.identity()..setEntry(3, 2, 0.001);
  if (axis == _SpinAxis.x) {
    matrix.rotateX(angle);
  } else {
    matrix.rotateY(angle);
  }
  return Transform(
    transform: matrix,
    alignment: Alignment.center,
    child: child,
  );
}

/// $[rainbow] の色相回転行列（[ColorFilter.matrix] 用の 4x5 行列）。
List<double> _hueRotationMatrix(double degrees) {
  final rad = degrees * math.pi / 180.0;
  final cosA = math.cos(rad);
  final sinA = math.sin(rad);
  const double lumR = 0.213;
  const double lumG = 0.715;
  const double lumB = 0.072;

  final a00 = lumR + (1 - lumR) * cosA + (-lumR) * sinA;
  final a01 = lumG + (-lumG) * cosA + (-lumG) * sinA;
  final a02 = lumB + (-lumB) * cosA + (1 - lumB) * sinA;

  final a10 = lumR + (-lumR) * cosA + (0.143) * sinA;
  final a11 = lumG + (1 - lumG) * cosA + (0.140) * sinA;
  final a12 = lumB + (-lumB) * cosA + (-0.283) * sinA;

  final a20 = lumR + (-lumR) * cosA + (-(1 - lumR)) * sinA;
  final a21 = lumG + (-lumG) * cosA + (lumG) * sinA;
  final a22 = lumB + (1 - lumB) * cosA + (lumB) * sinA;

  // prettier-ignore
  return [
    a00,
    a01,
    a02,
    0,
    0,
    a10,
    a11,
    a12,
    0,
    0,
    a20,
    a21,
    a22,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

// ---- キラキラウィジェット ----

/// $[sparkle] — 子ウィジェットの上にランダムな星型パーティクルを重ねる。
class _SparkleWidget extends StatefulWidget {
  final Widget child;
  const _SparkleWidget({required this.child});

  @override
  State<_SparkleWidget> createState() => _SparkleWidgetState();
}

class _SparkleParticle {
  double x;
  double y;
  double size;
  double opacity;
  double phase;
  _SparkleParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.phase,
  });
}

class _SparkleWidgetState extends State<_SparkleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_SparkleParticle> _particles = [];
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 6; i++) {
      _particles.add(
        _SparkleParticle(
          x: _rand.nextDouble(),
          y: _rand.nextDouble(),
          size: 4 + _rand.nextDouble() * 6,
          opacity: 0.0,
          phase: _rand.nextDouble() * 2 * math.pi,
        ),
      );
    }
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return CustomPaint(
          foregroundPainter: _SparklePainter(_particles, _ctrl.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SparklePainter extends CustomPainter {
  final List<_SparkleParticle> particles;
  final double t;

  _SparklePainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final v = math.sin((t * 2 * math.pi) + p.phase);
      final opacity = ((v + 1) / 2).clamp(0.0, 1.0);
      paint.color = Colors.yellow.withValues(alpha: opacity * 0.9);
      final cx = p.x * size.width;
      final cy = p.y * size.height;
      final s = p.size * (0.5 + 0.5 * opacity);
      _drawStar(canvas, paint, cx, cy, s);
    }
  }

  void _drawStar(Canvas canvas, Paint paint, double cx, double cy, double r) {
    final path = Path();
    const spikes = 4;
    final inner = r * 0.4;
    for (var i = 0; i < spikes * 2; i++) {
      final angle = (i * math.pi / spikes) - math.pi / 2;
      final radius = i.isEven ? r : inner;
      final x = cx + math.cos(angle) * radius;
      final y = cy + math.sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

// ---- 回転ウィジェット（レイアウトサイズを回転後の外接矩形に合わせる） ----

/// [Transform.rotate] は描画のみのトランスフォームでレイアウトサイズが変わらないため、
/// 回転後の外接矩形を正しいレイアウトサイズとして報告するカスタムウィジェット。
class _RotateWidget extends SingleChildRenderObjectWidget {
  final double angle;
  const _RotateWidget({required this.angle, required super.child});

  @override
  _RotateRenderBox createRenderObject(BuildContext context) =>
      _RotateRenderBox(angle: angle);

  @override
  void updateRenderObject(BuildContext context, _RotateRenderBox renderObject) {
    renderObject.angle = angle;
  }
}

class _RotateRenderBox extends RenderProxyBox {
  double _angle;

  _RotateRenderBox({required double angle}) : _angle = angle;

  double get angle => _angle;

  set angle(double value) {
    if (_angle == value) return;
    _angle = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // 回転後の外接矩形でレイアウトサイズを決めるため、
    // 子は unconstrained で自然なサイズを計算させる
    child!.layout(const BoxConstraints(), parentUsesSize: true);
    final w = child!.size.width;
    final h = child!.size.height;
    final cosA = math.cos(_angle).abs();
    final sinA = math.sin(_angle).abs();
    size = constraints.constrain(
      Size(w * cosA + h * sinA, w * sinA + h * cosA),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final childSize = child!.size;
    // 自ウィジェットの中心を軸に子ウィジェットを回転して描画する
    final m =
        Matrix4.translationValues(
            offset.dx + size.width / 2,
            offset.dy + size.height / 2,
            0,
          )
          ..multiply(Matrix4.rotationZ(_angle))
          ..multiply(
            Matrix4.translationValues(
              -childSize.width / 2,
              -childSize.height / 2,
              0,
            ),
          );
    context.pushTransform(
      needsCompositing,
      Offset.zero,
      m,
      (ctx, off) => ctx.paintChild(child!, off),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;
    final cosA = math.cos(-_angle);
    final sinA = math.sin(-_angle);
    final center = size.center(Offset.zero);
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final localX = dx * cosA - dy * sinA + child!.size.width / 2;
    final localY = dx * sinA + dy * cosA + child!.size.height / 2;
    return child!.hitTest(result, position: Offset(localX, localY));
  }
}

// ---- Ruby ベースライン補正ウィジェット ----

/// Column はデフォルトでベースラインを報告しないため、
/// 2番目の子（ベーステキスト）のベースラインを親に伝える RenderProxyBox。
class _RubyBaselineWrapper extends SingleChildRenderObjectWidget {
  const _RubyBaselineWrapper({required super.child});

  @override
  _RubyBaselineRenderBox createRenderObject(BuildContext context) =>
      _RubyBaselineRenderBox();
}

class _RubyBaselineRenderBox extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    // IntrinsicWidth などの RenderProxyBox を透過して RenderFlex (Column) を探す
    RenderBox? current = child;
    while (current != null && current is! RenderFlex) {
      current = current is RenderProxyBox ? current.child : null;
    }
    if (current is! RenderFlex) {
      return super.computeDistanceToActualBaseline(baseline);
    }

    // Column の最初の子（ルビ読み）を取得し、次のノード（ベーステキスト）へ進む
    final firstChild = current.firstChild;
    if (firstChild == null) {
      return super.computeDistanceToActualBaseline(baseline);
    }
    final secondChild = (firstChild.parentData as FlexParentData?)?.nextSibling;
    if (secondChild == null) {
      return super.computeDistanceToActualBaseline(baseline);
    }

    // ベーステキスト（2番目の子）の y オフセット + そのベースライン距離を返す
    final secondOffsetDy =
        (secondChild.parentData as FlexParentData?)?.offset.dy;
    if (secondOffsetDy == null) return null;
    final childBaseline = secondChild.getDistanceToActualBaseline(baseline);
    if (childBaseline == null) return null;

    return secondOffsetDy + childBaseline;
  }
}
