import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/draft_local_file_model.dart';
import '../../data/models/draft_model.dart';
import '../../data/models/drive_file_model.dart';
import '../../data/local/hive_service.dart';
import '../../core/constants/app_constants.dart';

final draftProvider = StateNotifierProvider<DraftNotifier, List<DraftModel>>(
  (ref) => DraftNotifier(),
);

class DraftNotifier extends StateNotifier<List<DraftModel>> {
  DraftNotifier() : super([]) {
    _load();
  }

  void _load() {
    final box = HiveService.draftsBox;
    final drafts = box.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    state = drafts;
  }

  Future<String> saveDraft({
    required String text,
    String visibility = AppConstants.visibilityPublic,
    String? existingId,
    List<DriveFileModel> files = const [],
    String? cw,
    bool isSensitive = false,
    List<DraftLocalFileModel> localFiles = const [],
  }) async {
    final box = HiveService.draftsBox;
    final id = existingId ?? const Uuid().v4();
    final draft = DraftModel(
      id: id,
      text: text,
      visibility: visibility,
      savedAt: DateTime.now(),
      files: files,
      cw: cw,
      isSensitive: isSensitive,
      localFiles: localFiles,
    );
    await box.put(id, draft);
    _load();
    return id;
  }

  Future<void> deleteDraft(String id) async {
    await HiveService.draftsBox.delete(id);
    _load();
  }

  DraftModel? getDraft(String id) {
    return HiveService.draftsBox.get(id);
  }

  /// 実体が端末から消えたローカル添付を下書きから取り除き、取り除いた件数を返す。
  ///
  /// ピッカーが返すパスはキャッシュ領域を指すことがあり、OSのキャッシュ削除で
  /// 実体だけ消える。一覧の描画時ではなく下書きを開いたときにだけ呼ぶこと。
  /// 外部ストレージが一時的にマウントされていないだけの場合にも「消えた」と
  /// 判定してしまうため、ユーザーの明示的な操作に紐付けて実行する。
  ///
  /// 保存日時は更新しない（一覧の並び順が勝手に変わらないようにするため）。
  Future<int> pruneMissingLocalFiles(String id) async {
    final box = HiveService.draftsBox;
    final draft = box.get(id);
    if (draft == null || draft.localFiles.isEmpty) return 0;

    final existing = draft.localFiles
        .where((f) => File(f.path).existsSync())
        .toList();
    final removed = draft.localFiles.length - existing.length;
    if (removed == 0) return 0;

    await box.put(
      id,
      DraftModel(
        id: draft.id,
        text: draft.text,
        visibility: draft.visibility,
        savedAt: draft.savedAt,
        files: draft.files,
        cw: draft.cw,
        isSensitive: draft.isSensitive,
        localFiles: existing,
      ),
    );
    _load();
    return removed;
  }
}
