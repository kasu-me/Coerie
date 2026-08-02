import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coerie/core/services/cache_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/mfm_content.dart';

class OgpData {
  final String title;
  final String? imageUrl;
  final String? description;
  final String url;

  const OgpData({
    required this.title,
    this.imageUrl,
    this.description,
    required this.url,
  });
}

String? _parseOgTag(String html, String property) {
  // property before content
  final r1 = RegExp(
    "<meta[^>]+property=[\"']$property[\"'][^>]+content=[\"']([^\"']*)[\"']",
    caseSensitive: false,
  );
  // content before property
  final r2 = RegExp(
    "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']$property[\"']",
    caseSensitive: false,
  );
  return r1.firstMatch(html)?.group(1) ?? r2.firstMatch(html)?.group(1);
}

/// OGP 取得用の Dio。リクエストごとに生成すると接続プールを使い回せないため共有する。
final _ogpDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Coerie/1.0)',
      'Accept': 'text/html',
    },
  ),
);

/// 読み込む HTML の上限バイト数。
/// og: メタタグは `<head>` にあるため先頭だけ読めば足りる。上限を設けないと
/// 巨大なページで通信量とメモリを浪費する。
const _maxHtmlBytes = 128 * 1024;

/// ページ先頭の最大 [_maxHtmlBytes] バイトだけをストリームで読み取る。
Future<String?> _fetchHtmlHead(String url) async {
  final res = await _ogpDio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      followRedirects: true,
      validateStatus: (s) => s != null && s < 400,
    ),
  );
  final body = res.data;
  if (body == null) return null;

  final bytes = <int>[];
  // 上限に達したら break でストリームを解約し、残りの受信を打ち切る
  await for (final chunk in body.stream) {
    bytes.addAll(chunk);
    if (bytes.length >= _maxHtmlBytes) break;
  }
  // 文字コードは UTF-8 を前提とし、壊れたバイト列は置換文字で読み飛ばす
  return utf8.decode(bytes, allowMalformed: true);
}

final ogpProvider = FutureProvider.autoDispose.family<OgpData?, String>((
  ref,
  url,
) async {
  // 取得結果は一定時間保持する。autoDispose のみだとカードがスクロールで
  // 画面外に出るたびに破棄され、戻るたびに再取得が走ってしまう。
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);

  try {
    final html = await _fetchHtmlHead(url);
    if (html == null) return null;

    final title = _parseOgTag(html, 'og:title');
    if (title == null || title.isEmpty) return null;

    return OgpData(
      title: title,
      imageUrl: _parseOgTag(html, 'og:image'),
      description: _parseOgTag(html, 'og:description'),
      url: url,
    );
  } catch (_) {
    return null;
  }
});

class OgpCard extends ConsumerWidget {
  final String url;
  const OgpCard({super.key, required this.url});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ogpAsync = ref.watch(ogpProvider(url));
    return ogpAsync.maybeWhen(
      data: (ogp) {
        if (ogp == null) return const SizedBox.shrink();
        return _OgpCardContent(ogp: ogp);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _OgpCardContent extends StatelessWidget {
  final OgpData ogp;
  const _OgpCardContent({required this.ogp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domain = Uri.tryParse(ogp.url)?.host ?? ogp.url;

    return GestureDetector(
      onTap: () => openMfmUrl(context, ogp.url),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ogp.imageUrl != null)
                SizedBox(
                  width: 80,
                  child: CachedNetworkImage(
                    cacheManager: AppCacheManager(),
                    imageUrl: ogp.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined, size: 24),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ogp.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (ogp.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          ogp.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        domain,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
