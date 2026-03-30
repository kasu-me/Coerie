import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

final ogpProvider = FutureProvider.family<OgpData?, String>((ref, url) async {
  try {
    final dio = Dio();
    final res = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 400,
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; Coerie/1.0)',
          'Accept': 'text/html',
        },
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    final html = res.data;
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
      onTap: () async {
        final uri = Uri.tryParse(ogp.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
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
                    imageUrl: ogp.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
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
