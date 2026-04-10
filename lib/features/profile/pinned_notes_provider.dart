import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/misskey_api_provider.dart';

// プロフィールのピン留め投稿を取得するプロバイダー（外部から invalidate 可能）
final pinnedNotesProvider = FutureProvider.family<List<NoteModel>, String>((
  ref,
  userId,
) async {
  final api = ref.watch(misskeyApiProvider);
  if (api == null) return [];
  return api.getUserPinnedNotes(userId);
});
