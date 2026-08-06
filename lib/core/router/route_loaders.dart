import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/antenna_model.dart';
import '../../data/models/clip_model.dart';
import '../../data/models/page_model.dart';
import '../../data/models/user_list_model.dart';
import '../../data/remote/misskey_api.dart';
import '../../features/clips/clip_notes_screen.dart';
import '../../features/pages/page_view_screen.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/utils/home_tab_helper.dart';

/// ルート解決中に出す、AppBarだけの読み込み画面。
class RouteLoadingScaffold extends StatelessWidget {
  const RouteLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// ルート解決に失敗したとき、または解決に必要な前提（ログイン状態など）が
/// 揃っていないときに出す画面。
class RouteErrorScaffold extends StatelessWidget {
  final String message;

  const RouteErrorScaffold({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(), body: Center(child: Text(message)));
  }
}

class ClipLoader extends ConsumerWidget {
  final String clipId;
  final String? host;
  const ClipLoader({super.key, required this.clipId, this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MisskeyApi? api = (host != null && host!.isNotEmpty)
        ? MisskeyApi(host: host!)
        : ref.read(misskeyApiProvider);

    if (api == null) {
      return const RouteErrorScaffold(message: '読み込むにはアカウントが必要です');
    }

    return FutureBuilder<ClipModel>(
      future: api.getClip(clipId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RouteLoadingScaffold();
        }
        if (snapshot.hasError) {
          return RouteErrorScaffold(
            message: 'クリップの読み込みに失敗しました: ${snapshot.error}',
          );
        }
        final clip = snapshot.data!;
        return ClipNotesScreen(clip: clip, host: host);
      },
    );
  }
}

/// `@user/pages/<name>` 形式のURLからページを解決して閲覧画面を出す。
///
/// `pages/show` は自インスタンスのページしか返さないため、[host] が
/// アクティブアカウントと異なる場合はそのホストへ未認証で問い合わせる。
class PageByNameLoader extends ConsumerStatefulWidget {
  final String username;
  final String pageName;
  final String? host;

  const PageByNameLoader({
    super.key,
    required this.username,
    required this.pageName,
    this.host,
  });

  @override
  ConsumerState<PageByNameLoader> createState() => _PageByNameLoaderState();
}

class _PageByNameLoaderState extends ConsumerState<PageByNameLoader> {
  late Future<PageModel> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<PageModel> _fetch() async {
    final api = ref.apiForHost(widget.host);
    if (api == null) throw Exception('読み込むにはアカウントが必要です');
    return api.getPage(name: widget.pageName, username: widget.username);
  }

  /// 取得に失敗したときの逃げ道として元のページURLを組み立てる。
  String? get _sourceUrl {
    final host = widget.host ?? ref.read(activeAccountProvider)?.host;
    if (host == null || host.isEmpty) return null;
    return 'https://$host/@${widget.username}/pages/${widget.pageName}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PageModel>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RouteLoadingScaffold();
        }
        if (snapshot.hasError) {
          final url = _sourceUrl;
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ページの読み込みに失敗しました\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    if (url != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('ブラウザで開く'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        final page = snapshot.data!;
        return PageViewScreen(
          pageId: page.id,
          initialPage: page,
          host: widget.host,
        );
      },
    );
  }
}

// ─── リスト/アンテナ: IDで引いてタイムライン画面を出すローダー ─────────────

/// リスト・アンテナ共通の「一覧取得 → IDで検索 → 見つかった名前 or 既定タイトルで
/// タイムライン画面を表示」というローダー。
///
/// 両者はモデル型が異なるだけで手順が完全に同じため、型引数 [T] と
/// 取得/検索用のコールバックで汎用化している。
class SourceLookupLoader<T> extends ConsumerWidget {
  final String sourceId;
  final String tabType;
  final String timelinePrefix;
  final String defaultTitle;
  final String errorMessage;
  final Future<List<T>> Function(MisskeyApi api) fetchAll;
  final String Function(T item) idOf;
  final String Function(T item) nameOf;

  const SourceLookupLoader({
    super.key,
    required this.sourceId,
    required this.tabType,
    required this.timelinePrefix,
    required this.defaultTitle,
    required this.errorMessage,
    required this.fetchAll,
    required this.idOf,
    required this.nameOf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MisskeyApi? api = ref.read(misskeyApiProvider);

    if (api == null) {
      return const RouteErrorScaffold(message: '読み込むにはアカウントが必要です');
    }

    return FutureBuilder<T?>(
      future: () async {
        final items = await fetchAll(api);
        for (final item in items) {
          if (idOf(item) == sourceId) return item;
        }
        return null;
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RouteLoadingScaffold();
        }
        if (snapshot.hasError) {
          return RouteErrorScaffold(message: '$errorMessage: ${snapshot.error}');
        }
        final item = snapshot.data;
        final name = item != null ? nameOf(item) : '';
        final title = name.isNotEmpty ? name : defaultTitle;
        return SourceTimelineScreen(
          sourceId: sourceId,
          name: title,
          tabType: tabType,
          timelinePrefix: timelinePrefix,
        );
      },
    );
  }
}

/// `/list/:listId` を id 指定のみで開いたとき（ブックマーク等）に、
/// リスト名を取得してから [SourceTimelineScreen] を出すためのローダー。
class ListLoader extends StatelessWidget {
  final String listId;
  const ListLoader({super.key, required this.listId});

  @override
  Widget build(BuildContext context) {
    return SourceLookupLoader<UserListModel>(
      sourceId: listId,
      tabType: AppConstants.tabTypeList,
      timelinePrefix: 'list',
      defaultTitle: 'リスト',
      errorMessage: 'リストの読み込みに失敗しました',
      fetchAll: (api) => api.getLists(),
      idOf: (l) => l.id,
      nameOf: (l) => l.name,
    );
  }
}

/// `/antenna/:antennaId` を id 指定のみで開いたときのローダー。[ListLoader] と同型。
class AntennaLoader extends StatelessWidget {
  final String antennaId;
  const AntennaLoader({super.key, required this.antennaId});

  @override
  Widget build(BuildContext context) {
    return SourceLookupLoader<AntennaModel>(
      sourceId: antennaId,
      tabType: AppConstants.tabTypeAntenna,
      timelinePrefix: 'antenna',
      defaultTitle: 'アンテナ',
      errorMessage: 'アンテナの読み込みに失敗しました',
      fetchAll: (api) => api.getAntennas(),
      idOf: (a) => a.id,
      nameOf: (a) => a.name,
    );
  }
}

// ─── List/Antenna timeline screen with "add to home tab" menu ───────────────

/// リスト・アンテナ共通の「ホームタブに追加」メニュー付きタイムライン画面。
/// [timelinePrefix] は timelineType の接頭辞（'list' / 'antenna'）、
/// [tabType] はタブ設定に保存する種別（AppConstants.tabTypeList など）。
class SourceTimelineScreen extends ConsumerStatefulWidget {
  final String sourceId;
  final String name;
  final String tabType;
  final String timelinePrefix;
  const SourceTimelineScreen({
    super.key,
    required this.sourceId,
    required this.name,
    required this.tabType,
    required this.timelinePrefix,
  });

  @override
  ConsumerState<SourceTimelineScreen> createState() =>
      _SourceTimelineScreenState();
}

class _SourceTimelineScreenState extends ConsumerState<SourceTimelineScreen> {
  Future<void> _addToHomeTab() async {
    await addToHomeTab(
      context,
      ref,
      tabType: widget.tabType,
      sourceId: widget.sourceId,
      defaultLabel: widget.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_tab') _addToHomeTab();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_tab',
                child: Row(
                  children: [
                    Icon(Icons.add_to_photos_outlined),
                    SizedBox(width: 8),
                    Text('ホームタブに追加'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TimelineScreen(
        timelineType: '${widget.timelinePrefix}:${widget.sourceId}',
      ),
    );
  }
}
