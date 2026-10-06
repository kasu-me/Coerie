import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_model.dart';
import '../providers/custom_emoji_provider.dart';
import '../utils/emoji_utils.dart';
import 'mfm_content.dart';

/// ユーザーの表示名を、名前中のカスタム絵文字・Unicode 絵文字を画像化して描画する。
///
/// 既定で1行に収め、はみ出しは省略記号にする。
/// スタイルは [Text] と同様に周囲の [DefaultTextStyle] を引き継ぐ。
class UserNameText extends ConsumerWidget {
  final UserModel user;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// 名前の後ろに続ける文言（例: 「 がリノート」）。
  ///
  /// 名前と同じ行で省略記号の対象にするため、別ウィジェットに分けず同じテキストに含める。
  /// plain モードは絵文字以外の記法を解釈しないので、文言がMFMとして化けることはない。
  final String suffix;

  const UserNameText(
    this.user, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MfmContent(
      text: '${user.displayName}$suffix',
      // EmojiResolver にユーザー絵文字専用の枠はないが、noteEmojis と同じく
      // 「インスタンス一覧より優先する、この表示対象に付随した絵文字」として扱える。
      emojiResolver: EmojiResolver(
        noteEmojis: user.emojis,
        instanceEmojis: ref.watch(customEmojiUrlMapProvider),
      ),
      style: style,
      plain: true,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
