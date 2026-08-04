/// ノートに対する自分の状態（notes/state）。
class NoteStateModel {
  final bool isFavorited;
  final bool isMutedThread;

  /// スレッドの返信通知を購読しているか。
  final bool isWatching;

  const NoteStateModel({
    this.isFavorited = false,
    this.isMutedThread = false,
    this.isWatching = false,
  });

  factory NoteStateModel.fromJson(Map<String, dynamic> json) {
    return NoteStateModel(
      isFavorited: json['isFavorited'] as bool? ?? false,
      isMutedThread: json['isMutedThread'] as bool? ?? false,
      isWatching: json['isWatching'] as bool? ?? false,
    );
  }
}
