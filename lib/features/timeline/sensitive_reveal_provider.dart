import 'package:flutter_riverpod/flutter_riverpod.dart';

/// センシティブ指定の添付ファイルのうち、ぼかしを解除したもののファイルID集合。
///
/// ウィジェットの State で持つと、ストリーミングでの新着挿入や
/// 画面外へのスクロールで NoteCard が作り直された際に解除状態が失われるため、
/// アプリ全体で保持する。同じノートを詳細画面などで開いた場合にも状態を揃えたい
/// ので、ノート単位ではなくファイル単位で持つ。
/// 解除はその場限りの操作という位置付けのため永続化はしない（アプリ終了で元に戻る）。
class SensitiveRevealNotifier extends StateNotifier<Set<String>> {
  SensitiveRevealNotifier() : super(const {});

  void reveal(String fileId) {
    if (state.contains(fileId)) return;
    state = {...state, fileId};
  }

  void hide(String fileId) {
    if (!state.contains(fileId)) return;
    state = {...state}..remove(fileId);
  }
}

final sensitiveRevealProvider =
    StateNotifierProvider<SensitiveRevealNotifier, Set<String>>(
      (ref) => SensitiveRevealNotifier(),
    );
