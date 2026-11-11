import 'drive_file_model.dart';
import 'note_model.dart';

/// サーバー側に保存されたノートの下書き（Misskey の NoteDraft）。
///
/// アプリの「下書き」機能（Hive の DraftModel）とは別物。Misskey では予約投稿が
/// `isActuallyScheduled` の立った下書きとして表現されるため、予約投稿の管理に使う。
class NoteDraftModel {
  final String id;
  final DateTime createdAt;
  final String? text;
  final String? cw;
  final String visibility;
  final List<String> visibleUserIds;
  final List<DriveFileModel> files;
  final String? replyId;
  final String? renoteId;
  final NoteModel? reply;
  final NoteModel? renote;
  final NoteDraftPoll? poll;
  final String? channelId;
  final String? channelName;

  /// 以下3つはアプリの投稿画面では編集しないが、Misskey Web で予約したものを
  /// 編集したときに消さないよう、更新時にそのまま送り返すために保持する。
  final bool localOnly;
  final String? reactionAcceptance;
  final String? hashtag;

  final DateTime? scheduledAt;
  final bool isActuallyScheduled;

  const NoteDraftModel({
    required this.id,
    required this.createdAt,
    this.text,
    this.cw,
    this.visibility = 'public',
    this.visibleUserIds = const [],
    this.files = const [],
    this.replyId,
    this.renoteId,
    this.reply,
    this.renote,
    this.poll,
    this.channelId,
    this.channelName,
    this.localOnly = false,
    this.reactionAcceptance,
    this.hashtag,
    this.scheduledAt,
    this.isActuallyScheduled = false,
  });

  /// 予約日時を過ぎても残っている予約。
  ///
  /// サーバーは投稿に成功すると下書きを削除し、失敗した場合は残したまま
  /// `scheduledNotePostFailed` 通知を出す。そのため「日時を過ぎて残っている」
  /// ことが失敗の目印になる。ただし予約日時ちょうどはジョブキューが処理中の
  /// ことがあるため、少し猶予を置いてから失敗とみなす。
  bool get isPostFailed {
    final at = scheduledAt;
    if (!isActuallyScheduled || at == null) return false;
    return DateTime.now().isAfter(at.add(const Duration(minutes: 1)));
  }

  factory NoteDraftModel.fromJson(
    Map<String, dynamic> json, {
    String host = '',
  }) {
    final filesJson = json['files'] as List<dynamic>? ?? const [];
    final channel = json['channel'] as Map<String, dynamic>?;
    return NoteDraftModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      text: json['text'] as String?,
      cw: json['cw'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      visibleUserIds: (json['visibleUserIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      files: filesJson
          .map((f) => DriveFileModel.fromJson(f as Map<String, dynamic>))
          .toList(),
      replyId: json['replyId'] as String?,
      renoteId: json['renoteId'] as String?,
      reply: json['reply'] is Map<String, dynamic>
          ? NoteModel.fromJson(
              json['reply'] as Map<String, dynamic>,
              host: host,
            )
          : null,
      renote: json['renote'] is Map<String, dynamic>
          ? NoteModel.fromJson(
              json['renote'] as Map<String, dynamic>,
              host: host,
            )
          : null,
      poll: json['poll'] is Map<String, dynamic>
          ? NoteDraftPoll.fromJson(json['poll'] as Map<String, dynamic>)
          : null,
      channelId: json['channelId'] as String?,
      channelName: channel?['name'] as String?,
      localOnly: json['localOnly'] as bool? ?? false,
      reactionAcceptance: json['reactionAcceptance'] as String?,
      hashtag: json['hashtag'] as String?,
      scheduledAt: _parseDate(json['scheduledAt']),
      isActuallyScheduled: json['isActuallyScheduled'] as bool? ?? false,
    );
  }
}

/// 下書きの投票。
///
/// 期限は絶対日時の [expiresAt] と、投稿時点からの相対時間の [expiredAfter] の
/// どちらかで持つ。予約投稿では投稿時刻が後ろにずれるため相対指定が実用的。
class NoteDraftPoll {
  final List<String> choices;
  final bool multiple;
  final DateTime? expiresAt;
  final Duration? expiredAfter;

  const NoteDraftPoll({
    required this.choices,
    this.multiple = false,
    this.expiresAt,
    this.expiredAfter,
  });

  factory NoteDraftPoll.fromJson(Map<String, dynamic> json) {
    final after = (json['expiredAfter'] as num?)?.toInt();
    return NoteDraftPoll(
      choices: (json['choices'] as List<dynamic>? ?? const []).cast<String>(),
      multiple: json['multiple'] as bool? ?? false,
      expiresAt: _parseDate(json['expiresAt']),
      expiredAfter: after == null ? null : Duration(milliseconds: after),
    );
  }
}

/// NoteDraft の日時はフィールドによって UNIX ミリ秒（scheduledAt）と
/// ISO 8601 文字列（poll.expiresAt）が混在するため、両方を受け付ける。
DateTime? _parseDate(Object? raw) {
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
