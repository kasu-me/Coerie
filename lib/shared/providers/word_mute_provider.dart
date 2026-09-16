import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/muted_word_model.dart';
import '../utils/word_mute.dart';
import 'account_provider.dart';
import 'misskey_api_provider.dart';

/// サーバーに保存されているワードミュート設定（ソフト・ハードの両方）。
///
/// [misskeyApiProvider] を watch しているため、アカウント切り替え時は自動で取り直される。
/// 設定を変更した画面は invalidate して各一覧へ反映させること。
///
/// 失敗をここで握り潰さないのは、設定画面が「取得できなかった」ことを判別できずに
/// 空リストとして表示し、そこへ1件追加するとサーバー側の設定を丸ごと上書きして
/// しまうため。一覧側のミュート判定は [wordMuteFilterProvider] が
/// エラー時も空の判定器を返すことで巻き込まれないようにしている。
final mutedWordsProvider = FutureProvider<WordMuteSettings>((ref) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return WordMuteSettings.empty;
  return api.getWordMuteSettings();
});

/// ノート一覧へ適用するワードミュート判定器。
///
/// 取得前・取得失敗時は空の判定器（何もミュートしない）になる。取得完了後に
/// 値が変わるため、一覧を保持する StateNotifier 側は listen して再適用すること。
final wordMuteFilterProvider = Provider<WordMuteFilter>((ref) {
  final settings = ref
      .watch(mutedWordsProvider)
      .maybeWhen(data: (s) => s, orElse: () => WordMuteSettings.empty);
  if (settings.isEmpty) return WordMuteFilter.empty;
  return WordMuteFilter(
    words: settings.all,
    viewerUserId: ref.watch(activeAccountProvider)?.userId,
  );
});
