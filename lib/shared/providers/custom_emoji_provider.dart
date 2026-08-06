import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/custom_emoji_model.dart';
import 'misskey_api_provider.dart';

/// 接続先インスタンスのカスタム絵文字一覧。
///
/// 絵文字ピッカーだけでなく、ノート・通知・ページの MFM 描画からも参照される
/// アプリ横断のプロバイダー。アカウント切り替え時は [app.dart] で invalidate される。
final customEmojisProvider = FutureProvider<List<CustomEmojiModel>>((ref) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getEmojis();
});

/// 接続先インスタンスのカスタム絵文字の name→url マップ。
///
/// [customEmojisProvider] の生リストから一度だけ構築して以降は使い回す。
/// 描画側でこのマップを複製しないこと（[EmojiResolver] 経由で参照する）。
final customEmojiUrlMapProvider = Provider<Map<String, String>>((ref) {
  return ref
      .watch(customEmojisProvider)
      .maybeWhen(
        data: (list) => {
          for (final e in list)
            if (e.name.isNotEmpty && e.url != null) e.name: e.url!,
        },
        // 未取得・エラー時は空マップ。
        // 各ノートの emojis/reactionEmojis フィールドで補完される。
        orElse: () => const <String, String>{},
      );
});
