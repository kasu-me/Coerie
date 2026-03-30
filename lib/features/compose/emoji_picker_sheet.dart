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

class _EmojiPickerSheetState extends ConsumerState<EmojiPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                final filtered = _query.isEmpty
                    ? emojis
                    : emojis
                          .where(
                            (e) =>
                                (e['name'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(_query) ||
                                (e['aliases'] as List<dynamic>? ?? []).any(
                                  (a) => a.toString().toLowerCase().contains(
                                    _query,
                                  ),
                                ),
                          )
                          .toList();

                if (filtered.isEmpty) {
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
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final emoji = filtered[i];
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
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                        Icons.emoji_emotions,
                                        size: 24,
                                      ),
                                )
                              : const Icon(Icons.emoji_emotions, size: 24),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
