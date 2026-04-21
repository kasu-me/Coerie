import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mfm_parser/mfm_parser.dart' as mfm;
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

/// MFM (Markup language For Misskey) テキストをレンダリングするウィジェット。
///
/// [text] に MFM 記法を含む文字列を渡すと、太字・斜体・引用・コードブロック・
/// カスタム絵文字・URL リンクなどを適切に描画します。
class MfmContent extends StatelessWidget {
  final String text;
  final Map<String, String> emojiUrlMap;
  final TextStyle? style;
  final bool enableAnimations;
  final void Function(String username, String? host)? onMentionTap;

  const MfmContent({
    super.key,
    required this.text,
    this.emojiUrlMap = const {},
    this.style,
    this.enableAnimations = false,
    this.onMentionTap,
  });

  // ---- 静的ユーティリティ ----

  /// テキストを MFM パースして最初の URL を返す（OGP カード表示用）。
  static String? extractFirstUrl(String text) {
    try {
      final nodes = const mfm.MfmParser().parse(text);
      return _findFirstUrl(nodes);
    } catch (_) {
      return null;
    }
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

  static String _twemojiUrl(String emoji) {
    final runes = emoji.runes.toList();
    final filtered = <int>[];
    for (int i = 0; i < runes.length; i++) {
      if (runes[i] == 0xFE0F) {
        // キーキャップシーケンス（FE0F の直後が U+20E3）の場合のみ FE0F を保持
        if (i + 1 < runes.length && runes[i + 1] == 0x20E3) {
          filtered.add(runes[i]);
        }
        // それ以外のバリエーションセレクタ-16 は Twemoji ファイル名に含まれないため除外
      } else {
        filtered.add(runes[i]);
      }
    }
    final parts = filtered.map((r) => r.toRadixString(16)).join('-');
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$parts.png';
  }

  // ---- インスタンスヘルパー ----

  String? _resolveEmojiUrl(String name) {
    String? url = emojiUrlMap[name];
    if (url != null) return url;
    final atIdx = name.indexOf('@');
    if (atIdx >= 0) {
      url = emojiUrlMap[name.substring(0, atIdx)];
    }
    return url;
  }

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

  List<InlineSpan> _nodeToSpans(
    mfm.MfmNode node,
    TextStyle style,
    BuildContext ctx,
  ) {
    final theme = Theme.of(ctx);

    if (node is mfm.MfmText) {
      return [
        TextSpan(text: _stripVariationSelectors(node.text), style: style),
      ];
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
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              onMentionTap?.call(node.username, node.host);
            },
        ),
      ];
    }

    if (node is mfm.MfmHashTag) {
      return [
        TextSpan(
          text: '#${node.hashTag}',
          style: style.copyWith(color: theme.colorScheme.primary),
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
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(raw);
              if (uri != null) {
                // 例: https://host/clips/clipId -> アプリ内遷移
                if (uri.pathSegments.isNotEmpty &&
                    uri.pathSegments[0] == 'clips' &&
                    uri.pathSegments.length >= 2) {
                  final clipId = uri.pathSegments[1];
                  final host = uri.host;
                  final query = host.isNotEmpty
                      ? '?host=${Uri.encodeComponent(host)}'
                      : '';
                  ctx.push('/clips/$clipId$query');
                  return;
                }
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
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
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(node.url);
              if (uri != null) {
                if (uri.pathSegments.isNotEmpty &&
                    uri.pathSegments[0] == 'clips' &&
                    uri.pathSegments.length >= 2) {
                  final clipId = uri.pathSegments[1];
                  final host = uri.host;
                  final query = host.isNotEmpty
                      ? '?host=${Uri.encodeComponent(host)}'
                      : '';
                  ctx.push('/clips/$clipId$query');
                  return;
                }
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      ];
    }

    if (node is mfm.MfmEmojiCode) {
      final url = _resolveEmojiUrl(node.name);
      final emojiSize = style.fontSize ?? 20.0;
      if (url != null) {
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.translate(
              offset: Offset(0, emojiSize * 0.13),
              child: CachedNetworkImage(
                imageUrl: url,
                height: emojiSize,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerLeft,
                fadeInDuration: Duration.zero,
                placeholder: (_, __) =>
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
            offset: Offset(0, emojiSize * 0.13),
            child: CachedNetworkImage(
              imageUrl: _twemojiUrl(node.emoji),
              height: emojiSize,
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerLeft,
              fadeInDuration: Duration.zero,
              placeholder: (_, __) =>
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
          BorderStyle bs;
          switch (styleStr) {
            case 'hidden':
              bs = BorderStyle.none;
              break;
            case 'dotted':
            case 'dashed':
            case 'double':
            case 'groove':
            case 'ridge':
            case 'inset':
            case 'outset':
            case 'solid':
            default:
              bs = BorderStyle.solid;
          }
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
          final formatted =
              '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
          return [TextSpan(text: formatted, style: style)];
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
        if (!enableAnimations) return _buildSpans(children, style, ctx);
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
    final speed = double.tryParse(args['speed']?.toString() ?? '') ?? 1.0;

    Widget animated;
    switch (name) {
      case 'spin':
        animated = _SpinWidget(
          alternate: args.containsKey('alternate'),
          speed: speed,
          child: childWidget,
        );
        break;
      case 'shake':
        animated = _ShakeWidget(speed: speed, child: childWidget);
        break;
      case 'jump':
      case 'fall':
        animated = _JumpWidget(speed: speed, child: childWidget);
        break;
      case 'bounce':
        animated = _BounceWidget(speed: speed, child: childWidget);
        break;
      case 'jelly':
      case 'tada':
        animated = _JellyWidget(speed: speed, child: childWidget);
        break;
      case 'twitch':
        animated = _TwitchWidget(speed: speed, child: childWidget);
        break;
      case 'rainbow':
        animated = _RainbowWidget(speed: speed, child: childWidget);
        break;
      case 'sparkle':
        animated = _SparkleWidget(child: childWidget);
        break;
      default:
        animated = childWidget;
    }
    return [
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: animated),
    ];
  }

  // ---- テキスト正規化 ----

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
    // テーマの bodyMedium を基底として明示的に fontFamily を引き継いだうえで、
    // 呼び出し元から渡された style でフォントサイズ等を上書きする。
    // RichText は DefaultTextStyle を継承しないため、ここで合成しないと
    // テーマ指定のフォント（Noto Sans JP 等）が適用されず、フォントメトリクスが
    // 不安定になり文字の大きさが揃わない問題が起きる。
    final base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .merge(style)
        .copyWith(color: style?.color ?? theme.colorScheme.onSurface);

    List<mfm.MfmNode> nodes;
    try {
      nodes = const mfm.MfmParser().parse(text);
    } catch (_) {
      // パースエラー時はプレーンテキストで表示
      return RichText(
        text: TextSpan(text: text, style: base),
      );
    }

    return _buildNodeList(nodes, base, context);
  }
}

// ---- MFM アニメーションウィジェット ----

class _SpinWidget extends StatefulWidget {
  final Widget child;
  final bool alternate;
  final double speed;
  const _SpinWidget({
    required this.child,
    this.alternate = false,
    this.speed = 1.0,
  });

  @override
  State<_SpinWidget> createState() => _SpinWidgetState();
}

class _SpinWidgetState extends State<_SpinWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (1500 / widget.speed).round()),
    )..repeat(reverse: widget.alternate);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alternate) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.rotate(
          angle: (_ctrl.value - 0.5) * math.pi,
          child: child,
        ),
        child: widget.child,
      );
    }
    return RotationTransition(turns: _ctrl, child: widget.child);
  }
}

class _ShakeWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _ShakeWidget({required this.child, this.speed = 1.0});

  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (500 / widget.speed).round()),
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
      builder: (_, child) => Transform.translate(
        offset: Offset(3 * math.sin(_ctrl.value * 2 * math.pi * 3), 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _JumpWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _JumpWidget({required this.child, this.speed = 1.0});

  @override
  State<_JumpWidget> createState() => _JumpWidgetState();
}

class _JumpWidgetState extends State<_JumpWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (750 / widget.speed).round()),
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
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          -16 * math.sin(_ctrl.value * math.pi).clamp(0.0, 1.0),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _BounceWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _BounceWidget({required this.child, this.speed = 1.0});

  @override
  State<_BounceWidget> createState() => _BounceWidgetState();
}

class _BounceWidgetState extends State<_BounceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (500 / widget.speed).round()),
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
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -12 * math.sin(_ctrl.value * math.pi)),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _JellyWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _JellyWidget({required this.child, this.speed = 1.0});

  @override
  State<_JellyWidget> createState() => _JellyWidgetState();
}

class _JellyWidgetState extends State<_JellyWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (1000 / widget.speed).round()),
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
        final scale = 1.0 + 0.15 * math.sin(_ctrl.value * 2 * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

class _TwitchWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _TwitchWidget({required this.child, this.speed = 1.0});

  @override
  State<_TwitchWidget> createState() => _TwitchWidgetState();
}

class _TwitchWidgetState extends State<_TwitchWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (200 / widget.speed).round()),
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
        final t = _ctrl.value;
        final dx = 3 * math.sin(t * 2 * math.pi * 7);
        final dy = 2 * math.sin(t * 2 * math.pi * 13);
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: widget.child,
    );
  }
}

class _RainbowWidget extends StatefulWidget {
  final Widget child;
  final double speed;
  const _RainbowWidget({required this.child, this.speed = 1.0});

  @override
  State<_RainbowWidget> createState() => _RainbowWidgetState();
}

class _RainbowWidgetState extends State<_RainbowWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final s = widget.speed <= 0 ? 1.0 : widget.speed;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (3000 / s).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final hue = _ctrl.value * 360;
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(_hueRotationMatrix(hue)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
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
