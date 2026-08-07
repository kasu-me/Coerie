import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/cache_service.dart';
import '../../data/models/page_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/custom_emoji_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/utils/emoji_utils.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'providers/pages_provider.dart';
import 'widgets/page_block_view.dart';
import 'widgets/page_list_tile.dart';

/// ページ閲覧画面（`/pages/:pageId`）。
///
/// ブロックレンダラ（[PageBlockList]）で本文を描画し、いいねの
/// 追加・解除を行う。自分のページには `YOUR_PAGE` エラーになるため
/// いいねボタンを出さず、代わりに編集・削除を出す。
class PageViewScreen extends ConsumerStatefulWidget {
  final String pageId;

  /// 一覧から遷移してきた場合の初期値。取得完了まで仮表示に使う。
  final PageModel? initialPage;

  /// ページが置かれているインスタンス。ノート内のリンクから来た場合に付く。
  /// アクティブアカウントと異なるときは未認証で読むだけの表示になる。
  final String? host;

  const PageViewScreen({
    super.key,
    required this.pageId,
    this.initialPage,
    this.host,
  });

  @override
  ConsumerState<PageViewScreen> createState() => _PageViewScreenState();
}

class _PageViewScreenState extends ConsumerState<PageViewScreen> {
  PageModel? _page;
  Object? _error;
  bool _isLoading = false;
  bool _isTogglingLike = false;

  /// 埋め込みノートの取得キャッシュ。同一ページ内で同じノートを二重取得しない。
  PageNoteCache? _noteCache;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _load();
  }

  /// 他インスタンスのページを開いている（未認証アクセス）かどうか。
  bool get _isRemote => ref.isRemoteHost(widget.host);

  Future<void> _load() async {
    final api = ref.apiForHost(widget.host);
    if (api == null) {
      setState(() => _error = Exception('ログインが必要です'));
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      // 再読み込み時は埋め込みノートも取り直す
      _noteCache = PageNoteCache(api);
    });
    try {
      final page = await api.getPage(pageId: widget.pageId);
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isOwnPage {
    final page = _page;
    if (page == null || _isRemote) return false;
    final me = ref.read(activeAccountProvider);
    return me != null && me.userId == page.userId;
  }

  String? get _pageUrl {
    final page = _page;
    final host = widget.host ?? ref.read(activeAccountProvider)?.host;
    if (page == null || host == null || host.isEmpty) return null;
    final username = page.user?.username;
    if (username == null || username.isEmpty || page.name.isEmpty) return null;
    return 'https://$host/@$username/pages/${page.name}';
  }

  /// いいねを楽観的に反映し、失敗したら元に戻す。
  Future<void> _toggleLike() async {
    final page = _page;
    final api = ref.read(misskeyApiProvider);
    if (page == null || api == null || _isTogglingLike) return;

    final wasLiked = page.isLiked ?? false;
    final nextCount = page.likedCount + (wasLiked ? -1 : 1);
    setState(() {
      _isTogglingLike = true;
      _page = page.copyWith(
        isLiked: !wasLiked,
        likedCount: nextCount < 0 ? 0 : nextCount,
      );
    });

    try {
      if (wasLiked) {
        await api.unlikePage(page.id);
      } else {
        await api.likePage(page.id);
      }
      if (!mounted) return;
      // いいね一覧の内容が変わるため作り直させる
      final accountKey = ref.read(activeAccountProvider)?.id ?? '';
      ref.invalidate(likedPagesProvider(accountKey));
    } catch (e) {
      if (!mounted) return;
      // 失敗したので楽観的更新をロールバックする
      setState(() => _page = page);
      showApiErrorSnackBar(
        context,
        e,
        fallback: wasLiked ? 'いいねの解除に失敗しました' : 'いいねに失敗しました',
      );
    } finally {
      if (mounted) setState(() => _isTogglingLike = false);
    }
  }

  Future<void> _edit() async {
    final page = _page;
    if (page == null) return;
    await context.push('/pages/${page.id}/edit', extra: page);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    final accountKey = ref.read(activeAccountProvider)?.id ?? '';
    ref.read(myPagesProvider(accountKey).notifier).refresh();
  }

  Future<void> _delete() async {
    final page = _page;
    final api = ref.read(misskeyApiProvider);
    if (page == null || api == null) return;

    final ok = await confirmAction(
      context,
      ref,
      title: 'ページを削除',
      message: '「${page.title}」を削除しますか？この操作は取り消せません。',
      confirmLabel: '削除',
    );
    if (!ok || !mounted) return;

    try {
      await api.deletePage(page.id);
      if (!mounted) return;
      final accountKey = ref.read(activeAccountProvider)?.id ?? '';
      ref.read(myPagesProvider(accountKey).notifier).removeLocally(page.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ページを削除しました')));
      context.pop();
    } catch (e) {
      if (mounted) showApiErrorSnackBar(context, e, fallback: 'ページの削除に失敗しました');
    }
  }

  Future<void> _copyUrl() async {
    final url = _pageUrl;
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URLを取得できませんでした')));
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URLをコピーしました'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _shareAsNote() {
    final url = _pageUrl;
    final page = _page;
    if (url == null || page == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URLを取得できませんでした')));
      return;
    }
    final title = page.title.isNotEmpty ? page.title : page.name;
    context.push('/compose', extra: {'initialText': '$title\n$url'});
  }

  Future<void> _openInBrowser() async {
    final url = _pageUrl;
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URLを取得できませんでした')));
      }
      return;
    }
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ブラウザを開けませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final isOwn = _isOwnPage;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          page?.title.isNotEmpty == true ? page!.title : 'ページ',
          overflow: TextOverflow.ellipsis,
        ),
        // 操作はギャラリー画面と揃えてメニューに集約する。いいねは本文末尾。
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'browser':
                  _openInBrowser();
                case 'copy':
                  _copyUrl();
                case 'share_note':
                  _shareAsNote();
                case 'reload':
                  _load();
                case 'edit':
                  _edit();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'browser',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser),
                    SizedBox(width: 8),
                    Text('ブラウザで開く'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 8),
                    Text('URLをコピー'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share_note',
                child: Row(
                  children: [
                    Icon(Icons.edit_note),
                    SizedBox(width: 8),
                    Text('ノートで共有'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reload',
                enabled: !_isLoading,
                child: const Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('再読み込み'),
                  ],
                ),
              ),
              if (isOwn) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 8),
                      Text('編集'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 8),
                      Text('削除'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: SafeArea(bottom: true, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final page = _page;
    if (page == null) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
      return PagesErrorView(
        error: _error,
        message: 'ページの取得に失敗しました',
        onRetry: _load,
      );
    }

    final settings = ref.watch(settingsProvider);
    final config = PageRenderConfig(
      fileById: page.fileById,
      emojiResolver: EmojiResolver(
        instanceEmojis: ref.watch(customEmojiUrlMapProvider),
      ),
      noteCache: _noteCache,
      alignCenter: page.alignCenter,
      font: page.font,
      fontSize: settings.fontSize,
    );
    final fontFamily = config.fontFamily;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (page.eyeCatchingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: page.eyeCatchingImage!.url,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, _) => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => Container(
                  height: 160,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: page.alignCenter
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  page.title.isEmpty ? '(無題)' : page.title,
                  textAlign: page.alignCenter ? TextAlign.center : null,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: fontFamily,
                  ),
                ),
                if ((page.summary ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      page.summary!.trim(),
                      textAlign: page.alignCenter ? TextAlign.center : null,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: fontFamily,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // 他インスタンスのユーザーIDは自インスタンスで解決できないため、
                // リモート表示ではプロフィールへの導線を出さない
                _AuthorRow(page: page, enableProfileLink: !_isRemote),
                const SizedBox(height: 8),
                const Divider(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: page.content.isEmpty
                ? Text(
                    'このページには内容がありません',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  )
                : PageBlockList(blocks: page.content, config: config),
          ),
          const Divider(),
          _buildLikeRow(page, theme),
        ],
      ),
    );
  }

  /// いいねと更新日時の行。ギャラリー画面と同じく本文末尾に置く。
  ///
  /// 自分のページ（`YOUR_PAGE` になる）と他インスタンスのページ（未認証）は
  /// いいねできないため、件数だけの表示にする。
  Widget _buildLikeRow(PageModel page, ThemeData theme) {
    final updatedAt = Text(
      '更新: ${formatYmdHm(page.updatedAt)}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );

    if (_isOwnPage || _isRemote) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.favorite_border,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              '${page.likedCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const Spacer(),
            updatedAt,
          ],
        ),
      );
    }

    final isLiked = page.isLiked ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? theme.colorScheme.error : null,
            ),
            tooltip: isLiked ? 'いいねを解除' : 'いいね',
            onPressed: _isTogglingLike ? null : _toggleLike,
          ),
          Text('${page.likedCount}'),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(right: 8), child: updatedAt),
        ],
      ),
    );
  }
}

/// 作者の表示行。タップでプロフィールへ遷移する。
class _AuthorRow extends StatelessWidget {
  final PageModel page;

  /// プロフィールへ遷移できるか。他インスタンスのページでは false。
  final bool enableProfileLink;

  const _AuthorRow({required this.page, this.enableProfileLink = true});

  @override
  Widget build(BuildContext context) {
    final user = page.user;
    if (user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enableProfileLink
          ? () => context.push('/profile/${user.id}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(
                      user.avatarUrl!,
                      cacheManager: AppCacheManager(),
                    )
                  : null,
              child: user.avatarUrl == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                user.displayName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                user.acct,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
