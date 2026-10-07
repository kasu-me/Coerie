import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CW（注釈）付きノートのうち、本文を展開したもののノートID集合。
///
/// ウィジェットの State で持つと、ストリーミングでの新着挿入や
/// 画面外へのスクロールで NoteCard が作り直された際に展開状態が失われるため、
/// アプリ全体で保持する。センシティブのぼかし解除（sensitiveRevealProvider）と
/// 同じ方針で、永続化はしない（アプリ終了で折りたたみに戻る）。
class CwExpandNotifier extends StateNotifier<Set<String>> {
  CwExpandNotifier() : super(const {});

  void toggle(String noteId) {
    state = state.contains(noteId)
        ? ({...state}..remove(noteId))
        : {...state, noteId};
  }
}

final cwExpandProvider = StateNotifierProvider<CwExpandNotifier, Set<String>>(
  (ref) => CwExpandNotifier(),
);
