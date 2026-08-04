import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../core/errors/api_error_message.dart';
import '../../data/models/clip_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/widgets/api_error_snack_bar.dart';
import '../../shared/widgets/error_view.dart';

class ClipsScreen extends ConsumerStatefulWidget {
  final String? ownerUserId;
  final String? ownerUserName;

  const ClipsScreen({super.key, this.ownerUserId, this.ownerUserName});

  @override
  ConsumerState<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends ConsumerState<ClipsScreen>
    with SingleTickerProviderStateMixin {
  List<ClipModel> _clips = [];
  bool _isLoading = false;
  String? _error;

  // お気に入りタブ（自分のクリップを表示している場合のみ使用）
  List<ClipModel> _favorites = [];
  bool _favoritesLoading = false;
  String? _favoritesError;
  bool _favoritesLoaded = false;

  // false: newest first (降順), true: oldest first (昇順)
  bool _ascending = false;

  /// 自分のクリップを表示しているか。お気に入りタブはこの場合のみ出す。
  late final bool _isOwn;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    final active = ref.read(activeAccountProvider);
    _isOwn = widget.ownerUserId == null || widget.ownerUserId == active?.userId;
    if (_isOwn) {
      _tabController = TabController(length: 2, vsync: this)
        ..addListener(_onTabChanged);
    }
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// お気に入りタブは初めて開いたときにだけ読み込む。
  /// タブ切り替えで FAB とアクションの対象が変わるため再ビルドも行う。
  void _onTabChanged() {
    if (_tabController!.index == 1 && !_favoritesLoaded) {
      _loadFavorites();
    }
    setState(() {});
  }

  bool get _isFavoritesTabActive => _isOwn && _tabController!.index == 1;

  void _sortList(List<ClipModel> clips) {
    clips.sort((a, b) {
      return _ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    // 自分のクリップを見る場合（ownerUserId が自分のID、または未指定）は
    // clips/list エンドポイントを使用する（users/clips は公開クリップのみ返すため）
    try {
      final clips = await api.getClips(
        userId: _isOwn ? null : widget.ownerUserId,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _clips = clips;
          _sortList(_clips);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(e, fallback: 'クリップを取得できませんでした'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _favoritesLoading = true;
      _favoritesError = null;
    });
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      if (mounted) setState(() => _favoritesLoading = false);
      return;
    }
    try {
      final clips = await api.getMyFavoriteClips();
      if (mounted) {
        setState(() {
          _favorites = clips;
          _sortList(_favorites);
          _favoritesLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _favoritesError = apiErrorMessage(e, fallback: 'お気に入りの取得に失敗しました'),
        );
      }
    } finally {
      if (mounted) setState(() => _favoritesLoading = false);
    }
  }

  /// クリップのお気に入り登録・解除を切り替える。
  /// 成功後は再取得せず、手元の一覧に結果を反映する。
  Future<void> _toggleFavorite(ClipModel clip) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    final wasFavorited = clip.isFavorited ?? false;

    try {
      if (wasFavorited) {
        await api.unfavoriteClip(clip.id);
      } else {
        await api.favoriteClip(clip.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apiErrorMessage(
                e,
                fallback: wasFavorited ? 'お気に入りの解除に失敗しました' : 'お気に入りの登録に失敗しました',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final count = (clip.favoritedCount ?? 0) + (wasFavorited ? -1 : 1);
    final updated = clip.copyWith(
      isFavorited: !wasFavorited,
      favoritedCount: count < 0 ? 0 : count,
    );
    setState(() {
      final i = _clips.indexWhere((c) => c.id == clip.id);
      if (i >= 0) _clips[i] = updated;
      // 未読込のお気に入り一覧に触ると次回取得まで中途半端な状態になるため、
      // 読み込み済みのときだけ反映する。
      if (_favoritesLoaded) {
        _favorites.removeWhere((c) => c.id == clip.id);
        if (!wasFavorited) {
          _favorites.add(updated);
          _sortList(_favorites);
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFavorited ? 'お気に入りから削除しました' : 'お気に入りに追加しました'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ClipEditSheet(onSaved: _load),
    );
  }

  void _showEditSheet(ClipModel clip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ClipEditSheet(clip: clip, onSaved: _load),
    );
  }

  Future<void> _deleteClip(ClipModel clip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('クリップを削除'),
        content: Text('「${clip.name}」を削除しますか？この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.deleteClip(clip.id);
      if (mounted) {
        setState(() => _favorites.removeWhere((c) => c.id == clip.id));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: '削除に失敗しました');
      }
    }
  }

  Future<void> _copyClipUrl(ClipModel clip) async {
    final active = ref.read(activeAccountProvider);
    final host = active?.host ?? '';
    if (host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URLをコピーできませんでした')));
      }
      return;
    }
    final url = 'https://$host/clips/${clip.id}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ownerUserName != null
              ? '${widget.ownerUserName} のクリップ'
              : 'クリップ',
        ),
        bottom: _isOwn
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.bookmark_outline), text: 'マイクリップ'),
                  Tab(icon: Icon(Icons.star_outline), text: 'お気に入り'),
                ],
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _ascending ? '古い順（昇順）' : '新しい順（降順）',
            onPressed: () {
              setState(() {
                _ascending = !_ascending;
                _sortList(_clips);
                _sortList(_favorites);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: _isFavoritesTabActive ? _loadFavorites : _load,
          ),
        ],
      ),
      floatingActionButton: _isOwn && !_isFavoritesTabActive
          ? FloatingActionButton(
              onPressed: _showCreateSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        bottom: true,
        child: _isOwn
            ? TabBarView(
                controller: _tabController,
                children: [_buildBody(), _buildFavoritesBody()],
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_clips.isEmpty) {
      return _buildEmpty(
        onRefresh: _load,
        icon: Icons.bookmark_border,
        title: _isOwn ? 'クリップがありません' : '公開クリップがありません',
        description: _isOwn
            ? '右下の + ボタンでクリップを作成できます'
            : 'このユーザーは公開クリップを持っていないか、\nサーバーがこの機能に対応していません',
      );
    }
    return _buildClipList(clips: _clips, onRefresh: _load, isFavorites: false);
  }

  Widget _buildFavoritesBody() {
    if (_favoritesLoading && _favorites.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favoritesError != null) {
      return ErrorView(message: _favoritesError!, onRetry: _loadFavorites);
    }
    if (_favorites.isEmpty) {
      return _buildEmpty(
        onRefresh: _loadFavorites,
        icon: Icons.star_border,
        title: 'お気に入りのクリップがありません',
        description: 'クリップの ☆ ボタンでお気に入りに追加できます',
      );
    }
    return _buildClipList(
      clips: _favorites,
      onRefresh: _loadFavorites,
      isFavorites: true,
    );
  }

  Widget _buildEmpty({
    required Future<void> Function() onRefresh,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(title),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipList({
    required List<ClipModel> clips,
    required Future<void> Function() onRefresh,
    required bool isFavorites,
  }) {
    // お気に入りタブには他人のクリップも並ぶため、編集・削除は出さない
    final canManage = _isOwn && !isFavorites;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: clips.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final clip = clips[i];
          final isFavorited = clip.isFavorited ?? false;
          return ListTile(
            leading: Icon(
              clip.isPublic ? Icons.bookmark : Icons.bookmark_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(clip.name),
            subtitle: clip.description != null
                ? Text(
                    clip.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (clip.notesCount != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${clip.notesCount}件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                // 星と件数が離れると別々の数字に見えるため、間隔を詰めて隣接させる
                IconButton(
                  icon: Icon(
                    isFavorited ? Icons.star : Icons.star_border,
                    color: isFavorited
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: isFavorited ? 'お気に入りから削除' : 'お気に入りに追加',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 40,
                  ),
                  onPressed: () => _toggleFavorite(clip),
                ),
                if ((clip.favoritedCount ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${clip.favoritedCount}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'copy') _copyClipUrl(clip);
                    if (value == 'edit') _showEditSheet(clip);
                    if (value == 'delete') _deleteClip(clip);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: const [
                          Icon(Icons.copy),
                          SizedBox(width: 8),
                          Text('URLをコピー'),
                        ],
                      ),
                    ),
                    if (canManage) ...[
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
            onTap: () async {
              // 詳細画面でお気に入り状態が変わることがあるため戻り値で反映する
              final result = await context.push(
                '/clips/${clip.id}',
                extra: clip,
              );
              if (result is ClipModel) _applyClipUpdate(result);
            },
          );
        },
      ),
    );
  }

  /// 詳細画面から返ってきたクリップの状態を各一覧に反映する
  void _applyClipUpdate(ClipModel clip) {
    if (!mounted) return;
    setState(() {
      final i = _clips.indexWhere((c) => c.id == clip.id);
      if (i >= 0) _clips[i] = clip;
      if (_favoritesLoaded) {
        _favorites.removeWhere((c) => c.id == clip.id);
        if (clip.isFavorited ?? false) {
          _favorites.add(clip);
          _sortList(_favorites);
        }
      }
    });
  }
}

// ---- クリップ作成/編集ボトムシート ----

class _ClipEditSheet extends ConsumerStatefulWidget {
  final ClipModel? clip;
  final VoidCallback onSaved;

  const _ClipEditSheet({this.clip, required this.onSaved});

  @override
  ConsumerState<_ClipEditSheet> createState() => _ClipEditSheetState();
}

class _ClipEditSheetState extends ConsumerState<_ClipEditSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.clip;
    if (c != null) {
      _nameController.text = c.name;
      _descController.text = c.description ?? '';
      _isPublic = c.isPublic;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
      return;
    }

    setState(() => _isSaving = true);
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      if (widget.clip == null) {
        await api.createClip(
          name: name,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          isPublic: _isPublic,
        );
      } else {
        await api.updateClip(
          clipId: widget.clip!.id,
          name: name,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          isPublic: _isPublic,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showApiErrorSnackBar(context, e, fallback: '保存に失敗しました');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.clip != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'クリップを編集' : '新しいクリップを作成',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: _save,
                    child: Text(isEditing ? '保存' : '作成'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'タイトル',
                    hintText: 'クリップのタイトルを入力',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: '説明（任意）',
                    hintText: '説明を入力',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                  title: const Text('公開する'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
