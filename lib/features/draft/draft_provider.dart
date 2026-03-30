import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/draft_model.dart';
import '../../data/models/note_model.dart';
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
  }) async {
    final box = HiveService.draftsBox;
    final id = existingId ?? const Uuid().v4();
    final draft = DraftModel(
      id: id,
      text: text,
      visibility: visibility,
      savedAt: DateTime.now(),
      files: files,
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
}
