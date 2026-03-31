import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/providers/misskey_api_provider.dart';

// カスタム絵文字一覧プロバイダー
final customEmojisProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getEmojis();
});

/// サーバーのカスタム絵文字ピッカー。
/// 選択した絵文字の `name`（`:emoji_name:` 形式の中身）を返す。
class EmojiPickerSheet extends ConsumerStatefulWidget {
  const EmojiPickerSheet({super.key});

  @override
  ConsumerState<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends ConsumerState<EmojiPickerSheet>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _query = '';
  TabController? _tabController;
  List<String> _categories = [];
  Map<String, List<Map<String, dynamic>>> _byCategory = {};

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _buildCategories(List<Map<String, dynamic>> emojis) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in emojis) {
      final cat = (e['category'] as String?)?.trim() ?? '';
      map.putIfAbsent(cat, () => []).add(e);
    }
    // カテゴリ名順にソート（空文字は末尾）
    final cats = map.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    if (_categories.length != cats.length ||
        !_categories.every((c) => cats.contains(c))) {
      _tabController?.dispose();
      _tabController = TabController(length: cats.length, vsync: this);
      _categories = cats;
    }
    _byCategory = map;
  }

  Widget _emojiGrid(
    List<Map<String, dynamic>> emojis,
    ScrollController scrollController,
  ) {
    if (emojis.isEmpty) {
      return const Center(child: Text('絵文字が見つかりません'));
    }
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (_, i) {
        final emoji = emojis[i];
        final name = emoji['name'] as String? ?? '';
        final url = emoji['url'] as String?;
        return Tooltip(
          message: ':$name:',
          child: InkWell(
            onTap: () => Navigator.pop(context, name),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.emoji_emotions, size: 24),
                    )
                  : const Icon(Icons.emoji_emotions, size: 24),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final emojisAsync = ref.watch(customEmojisProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // ハンドル
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // タイトル
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '絵文字',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 検索
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '絵文字を検索...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          // 一覧
          Expanded(
            child: emojisAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('読み込みエラー: $e')),
              data: (emojis) {
                _buildCategories(emojis);

                // 検索中はフラットなグリッドを表示
                if (_query.isNotEmpty) {
                  final filtered = emojis.where((e) {
                    final name = (e['name'] as String? ?? '').toLowerCase();
                    final aliases = (e['aliases'] as List<dynamic>? ?? []);
                    return name.contains(_query) ||
                        aliases.any(
                          (a) =>
                              a.toString().toLowerCase().contains(_query),
                        );
                  }).toList();
                  return _emojiGrid(filtered, scrollController);
                }

                // カテゴリタブ表示
                if (_categories.isEmpty) {
                  return const Center(child: Text('絵文字が見つかりません'));
                }

                final tabCtrl = _tabController!;
                return Column(
                  children: [
                    TabBar(
                      controller: tabCtrl,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: _categories.map((c) {
                        final label = c.isEmpty ? '未分類' : c;
                        return Tab(
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: tabCtrl,
                        children: _categories.map((c) {
                          final list = _byCategory[c] ?? [];
                          return _emojiGrid(list, scrollController);
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}