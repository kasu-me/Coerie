import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/user_model.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../timeline/widgets/note_card.dart';

// ユーザー情報プロバイダー
final userProfileProvider = FutureProvider.family<UserModel, String>((
  ref,
  userId,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) throw Exception('未ログイン');
  return api.getUser(userId);
});

// ---- 投稿ページネーション ----
class _ProfileNotesState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool hasMore;

  const _ProfileNotesState({
    this.notes = const [],
    this.isLoading = false,
    this.hasMore = true,
  });

  _ProfileNotesState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? hasMore,
  }) => _ProfileNotesState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
  );
}

class _ProfileNotesNotifier extends StateNotifier<_ProfileNotesState> {
  final Ref _ref;
  final String userId;
  final bool withFiles;

  _ProfileNotesNotifier(this._ref, this.userId, {this.withFiles = false})
    : super(const _ProfileNotesState()) {
    fetch();
  }

  Future<void> fetch({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final untilId = loadMore && state.notes.isNotEmpty
          ? state.notes.last.id
          : null;
      final notes = await api.getUserNotes(
        userId: userId,
        limit: 20,
        withFiles: withFiles,
        untilId: untilId,
      );
      state = state.copyWith(
        isLoading: false,
        notes: loadMore ? [...state.notes, ...notes] : notes,
        hasMore: notes.length >= 20,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

typedef _NotesProviderKey = ({String userId, bool withFiles});

final _profileNotesProvider = StateNotifierProvider.autoDispose
    .family<_ProfileNotesNotifier, _ProfileNotesState, _NotesProviderKey>(
      (ref, p) => _ProfileNotesNotifier(ref, p.userId, withFiles: p.withFiles),
    );

class ProfileScreen extends ConsumerWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(e.toString().replaceFirst('Exception: ', '')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(userProfileProvider(userId)),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
        data: (user) => _ProfileBody(user: user, userId: userId),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  final UserModel user;
  final String userId;

  const _ProfileBody({required this.user, required this.userId});

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesState = ref.watch(
      _profileNotesProvider((userId: widget.userId, withFiles: false)),
    );
    final mediaState = ref.watch(
      _profileNotesProvider((userId: widget.userId, withFiles: true)),
    );
    final user = widget.user;

    return DefaultTabController(
      length: 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // バナー画像
                  if (user.bannerUrl != null)
                    CachedNetworkImage(
                      imageUrl: user.bannerUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, stack) =>
                          Container(color: theme.colorScheme.primaryContainer),
                    )
                  else
                    Container(color: theme.colorScheme.primaryContainer),
                  // グラデーション
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black45],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: user.avatarUrl != null
                            ? CachedNetworkImageProvider(user.avatarUrl!)
                            : null,
                        child: user.avatarUrl == null
                            ? const Icon(Icons.person, size: 36)
                            : null,
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (user.description != null) ...[
                    const SizedBox(height: 8),
                    Text(user.description!),
                  ],
                  if (user.followingCount != null ||
                      user.followersCount != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (user.followingCount != null) ...[
                          _CountChip(
                            count: user.followingCount!,
                            label: 'フォロー',
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (user.followersCount != null)
                          _CountChip(
                            count: user.followersCount!,
                            label: 'フォロワー',
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // タブバー
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                tabs: const [
                  Tab(text: '投稿'),
                  Tab(text: 'メディア'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _buildNotesList(notesState, (
              userId: widget.userId,
              withFiles: false,
            ), '投稿がありません'),
            _buildNotesList(mediaState, (
              userId: widget.userId,
              withFiles: true,
            ), 'メディア付きの投稿がありません'),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList(
    _ProfileNotesState state,
    _NotesProviderKey providerKey,
    String emptyMessage,
  ) {
    if (state.isLoading && state.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.notes.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          ref
              .read(_profileNotesProvider(providerKey).notifier)
              .fetch(loadMore: true);
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.notes.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == state.notes.length) {
            return state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return NoteCard(note: state.notes[i]);
        },
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;

  const _CountChip({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
