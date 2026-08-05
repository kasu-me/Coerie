import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/api_error_message.dart';
import '../../core/services/cache_service.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/models/gallery_post_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/utils/download_helper.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/mfm_content.dart';
import '../../shared/widgets/user_avatar.dart';
import 'providers/gallery_providers.dart';

/// ギャラリー投稿の詳細画面。
///
/// [initialPost] が渡されていれば即座に表示しつつ、裏で最新状態を取得して
/// 差し替える（一覧からの遷移で使う）。無い場合（ディープリンク等）は
/// 取得完了まで読み込み中表示にする。
class GalleryDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  final GalleryPostModel? initialPost;

  /// 投稿が置かれているインスタンス。ノート内のリンクから来た場合に付く。
  /// アクティブアカウントと異なるときは未認証で読むだけの表示になる。
  final String? host;

  const GalleryDetailScreen({
    super.key,
    required this.postId,
    this.initialPost,
    this.host,
  });

  @override
  ConsumerState<GalleryDetailScreen> createState() =>
      _GalleryDetailScreenState();
}

class _GalleryDetailScreenState extends ConsumerState<GalleryDetailScreen> {
  GalleryPostModel? _post;
  bool _isLoading = false;
  String? _error;
  bool _isTogglingLike = false;
  bool _sensitiveRevealed = false;
  int _imageIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _pageController = PageController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 他インスタンスの投稿を開いている（未認証アクセス）かどうか。
  bool get _isRemote => ref.isRemoteHost(widget.host);

  Future<void> _load() async {
    final api = ref.apiForHost(widget.host);
    if (api == null) return;
    if (_post == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final fetched = await api.getGalleryPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = fetched;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_post == null) {
          _error = apiErrorMessage(e, fallback: '投稿の取得に失敗しました');
        }
      });
    }
  }

  bool get _isOwnPost {
    final post = _post;
    if (post == null || _isRemote) return false;
    final myId = ref.read(activeAccountProvider)?.userId;
    return myId != null && post.userId == myId;
  }

  /// この投稿のインスタンス上でのURL。ホスト不明なら null。
  String? get _postUrl {
    final host = widget.host ?? ref.read(activeAccountProvider)?.host;
    if (host == null || host.isEmpty) return null;
    return 'https://$host/gallery/${widget.postId}';
  }

  Future<void> _copyUrl() async {
    final url = _postUrl;
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

  Future<void> _openInBrowser() async {
    final url = _postUrl;
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

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null || _isTogglingLike || _isOwnPost) return;
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    final wasLiked = post.isLiked ?? false;
    final optimistic = post.copyWith(
      isLiked: !wasLiked,
      likedCount: (post.likedCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 31),
    );
    setState(() {
      _post = optimistic;
      _isTogglingLike = true;
    });
    try {
      if (wasLiked) {
        await api.unlikeGalleryPost(post.id);
      } else {
        await api.likeGalleryPost(post.id);
      }
      if (mounted) setState(() => _isTogglingLike = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _post = post; // ロールバック
        _isTogglingLike = false;
      });
      showApiErrorSnackBar(
        context,
        e,
        fallback: wasLiked ? 'いいねの解除に失敗しました' : 'いいねに失敗しました',
      );
    }
  }

  Future<void> _edit() async {
    final post = _post;
    if (post == null) return;
    final result = await context.push<GalleryPostModel>(
      '/gallery/${post.id}/edit',
      extra: post,
    );
    if (result != null && mounted) {
      setState(() => _post = result);
    }
  }

  Future<void> _delete() async {
    final post = _post;
    if (post == null) return;
    final confirmed = await confirmAction(
      context,
      ref,
      title: '投稿を削除',
      message: '「${post.title}」を削除しますか？この操作は取り消せません。',
      confirmLabel: '削除',
    );
    if (!confirmed || !mounted) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteGalleryPost(post.id);
      if (mounted) {
        Navigator.of(context).pop(GalleryDetailResult.deleted(post.id));
      }
    } catch (e) {
      if (mounted) showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
    }
  }

  void _openTag(String tag) {
    context.push('/search', extra: {'tab': 1, 'query': tag});
  }

  /// 他インスタンスのユーザーIDは自インスタンスで解決できないため、
  /// リモート表示ではプロフィールへ遷移しない。
  void _openUser(String userId) {
    if (_isRemote) return;
    context.push('/profile/$userId');
  }

  void _openFullscreen(int initialIndex) {
    final post = _post;
    if (post == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GalleryFullscreenViewer(
          files: post.files,
          initialIndex: initialIndex,
          title: post.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(
          context,
        ).pop(post != null ? GalleryDetailResult.updated(post) : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            post?.title ?? 'ギャラリー',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'browser':
                    _openInBrowser();
                  case 'copy':
                    _copyUrl();
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
                if (post != null && _isOwnPost) ...[
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
        body: _buildBody(post),
      ),
    );
  }

  Widget _buildBody(GalleryPostModel? post) {
    if (post == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error ?? '投稿を表示できません'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('再読み込み')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildImagePager(post),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openUser(post.userId),
                  child: Row(
                    children: [
                      UserAvatar(avatarUrl: post.user?.avatarUrl, radius: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.user?.displayName ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (post.user != null)
                              Text(
                                post.user!.acct,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(post.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  formatRelativeTime(post.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                if (post.description != null &&
                    post.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  MfmContent(text: post.description!, enableAnimations: true),
                ],
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in post.tags)
                        ActionChip(
                          label: Text('#$tag'),
                          onPressed: () => _openTag(tag),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                _buildLikeRow(post),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikeRow(GalleryPostModel post) {
    final theme = Theme.of(context);
    final isLiked = post.isLiked ?? false;
    // 自分の投稿にはいいねできない（YOUR_POST）。他インスタンスの投稿は
    // 未認証アクセスなのでいいねできない。どちらもボタンは表示しない。
    if (_isOwnPost || _isRemote) {
      return Row(
        children: [
          Icon(Icons.favorite_border, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Text('${post.likedCount} 件のいいね'),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? theme.colorScheme.error : null,
          ),
          tooltip: isLiked ? 'いいねを解除' : 'いいね',
          onPressed: _isTogglingLike ? null : _toggleLike,
        ),
        Text('${post.likedCount}'),
      ],
    );
  }

  Widget _buildImagePager(GalleryPostModel post) {
    final files = post.files;
    if (files.isEmpty) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Theme.of(context).colorScheme.outline,
            size: 48,
          ),
        ),
      );
    }

    Widget pager = AspectRatio(
      aspectRatio: 4 / 3,
      child: PageView.builder(
        controller: _pageController,
        itemCount: files.length,
        onPageChanged: (i) => setState(() => _imageIndex = i),
        itemBuilder: (context, i) {
          final file = files[i];
          return GestureDetector(
            onTap: (post.isSensitive && !_sensitiveRevealed)
                ? null
                : () => _openFullscreen(i),
            child: CachedNetworkImage(
              cacheManager: AppCacheManager(),
              imageUrl: file.url,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          );
        },
      ),
    );

    // isSensitive は投稿単位。ノートの添付画像と同じく、ぼかし＋タップで解除する。
    if (post.isSensitive && !_sensitiveRevealed) {
      pager = Stack(
        fit: StackFit.passthrough,
        children: [
          pager,
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: () => setState(() => _sensitiveRevealed = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'センシティブな内容です\nタップして表示',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        pager,
        if (files.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < files.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _imageIndex
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 画像の全画面ビューア（拡大縮小・ダウンロード対応）。
///
/// 計画書では既存の `media_player_screen.dart` の流用が指示されているが、
/// 同ファイルは動画/音声専用（VideoPlayerController ベース）で画像を
/// 再生できないため、drive_screen.dart の `_DriveImagePreviewScreen` と
/// 同様のパターンで専用ビューアを実装した。
class _GalleryFullscreenViewer extends StatefulWidget {
  final List<DriveFileModel> files;
  final int initialIndex;
  final String title;

  const _GalleryFullscreenViewer({
    required this.files,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<_GalleryFullscreenViewer> createState() =>
      _GalleryFullscreenViewerState();
}

class _GalleryFullscreenViewerState extends State<_GalleryFullscreenViewer> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _download(DriveFileModel file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('ダウンロードを開始します...')));
    try {
      await DownloadHelper.downloadToPublicDownloads(
        url: file.url,
        fileName: file.name,
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('「${file.name}」をDownloadフォルダに保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('ダウンロードに失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.files.length > 1
              ? '${widget.title} (${_index + 1}/${widget.files.length})'
              : widget.title,
        ),
        actions: [
          PopupMenuButton<String>(
            color: theme.colorScheme.surface,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              final file = widget.files[_index];
              if (v == 'download') _download(file);
              if (v == 'open') {
                launchUrl(
                  Uri.parse(file.url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded),
                    SizedBox(width: 12),
                    Text('ダウンロード'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser),
                    SizedBox(width: 12),
                    Text('ブラウザで開く'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final file = widget.files[i];
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Center(
              child: CachedNetworkImage(
                cacheManager: AppCacheManager(),
                imageUrl: file.url,
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
          );
        },
      ),
    );
  }
}
