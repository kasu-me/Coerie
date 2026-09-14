import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'draft_local_file_model.dart';
import 'drive_file_model.dart';

part 'draft_model_adapter.dart';

class DraftModel {
  final String id;
  final String text;
  final String visibility;
  final DateTime savedAt;
  final List<DriveFileModel> files;
  final String? cw;
  final bool isSensitive;

  /// まだアップロードしていない端末内の添付。実体はコピーせずパスのみ保持する。
  final List<DraftLocalFileModel> localFiles;

  /// 返信先ノートのID。ノート本体は保存せず、下書きを開くときに取得し直す。
  final String? replyId;

  /// 返信先ユーザーの acct。一覧に返信相手を出すためだけに持つ。
  ///
  /// 一覧で [replyId] からノートを引くと下書きの件数だけ通信が発生するため、
  /// 表示に要る最小限をここに写しておく。相手の改名には追従しない。
  final String? replyAcct;

  /// 引用元ノートのID。[replyId] と同じ理由でIDのみを保存する。
  final String? renoteId;

  /// 引用元ユーザーの acct。用途は [replyAcct] と同じ。
  final String? renoteAcct;

  DraftModel({
    required this.id,
    required this.text,
    required this.visibility,
    required this.savedAt,
    this.files = const [],
    this.cw,
    this.isSensitive = false,
    this.localFiles = const [],
    this.replyId,
    this.replyAcct,
    this.renoteId,
    this.renoteAcct,
  });
}
