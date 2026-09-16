import '../../data/models/muted_word_model.dart';
import '../../data/models/note_model.dart';

/// ワードミュートの判定器。
///
/// Misskey サーバーはワードミュートをタイムラインの取得結果から除外しない
/// （本家クライアントも受信後に自前で判定している）。そのため取得したノートを
/// 画面に載せる前に、この判定器で落とす必要がある。
class WordMuteFilter {
  final List<MutedWordModel> words;

  /// 閲覧中アカウントのユーザーID。自分の投稿はミュートしない（本家と同じ挙動）。
  final String? viewerUserId;

  const WordMuteFilter({required this.words, this.viewerUserId});

  static const WordMuteFilter empty = WordMuteFilter(words: []);

  bool get isEmpty => words.isEmpty;

  /// [note] を非表示にすべきか。
  ///
  /// リノートはカード上にリノート元の本文が表示されるため、リノート元も判定する。
  /// 返信先（reply）はカードに本文が出ないため対象外。
  bool isMuted(NoteModel note) {
    if (words.isEmpty) return false;
    if (_matches(note)) return true;
    final renote = note.renote;
    return renote != null && _matches(renote);
  }

  /// ミュート対象を取り除いたリストを返す。該当が無ければ元のリストをそのまま返す。
  List<NoteModel> apply(List<NoteModel> notes) {
    if (words.isEmpty) return notes;
    final visible = notes.where((n) => !isMuted(n)).toList();
    return visible.length == notes.length ? notes : visible;
  }

  bool _matches(NoteModel note) {
    if (viewerUserId != null && note.user.id == viewerUserId) return false;
    // 判定対象は CW と本文のみ（本家 checkWordMute と同じ）。
    final text = '${note.cw ?? ''}\n${note.text ?? ''}'.trim();
    if (text.isEmpty) return false;
    return words.any((w) => w.matches(text));
  }
}
