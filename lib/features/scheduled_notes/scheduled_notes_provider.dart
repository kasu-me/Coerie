import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/note_draft_model.dart';
import '../../data/remote/misskey_api.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';

/// アカウントごとの予約投稿の上限件数。0 は予約投稿を使えないことを表す。
///
/// 投稿画面ではアクティブでないアカウントでも投稿できるため、アクティブ
/// アカウント依存の [misskeyApiProvider] ではなくアカウントIDで引く。
///
/// 判定できた値だけを保持し続ける。通信失敗で判定できなかった場合は 0 を返しつつ
/// 保持はしないので、次に画面を開いたときに取り直す（一時的な失敗で予約の導線を
/// 消したままにしないため）。
final scheduledNoteLimitProvider = FutureProvider.autoDispose
    .family<int, String>((ref, accountId) async {
      // 表示名やアイコンの同期だけで取り直さないよう、接続情報だけを見る。
      final connection = ref.watch(
        accountProvider.select((accounts) {
          for (final a in accounts) {
            if (a.id == accountId) return (host: a.host, token: a.token);
          }
          return null;
        }),
      );
      if (connection == null) return 0;

      final api = MisskeyApi(host: connection.host, token: connection.token);
      final limit = await api.fetchScheduledNoteLimit();
      if (limit == null) return 0;
      ref.keepAlive();
      return limit;
    });

/// アクティブアカウントの予約投稿一覧（予約日時の早い順）。
///
/// 予約件数はロールポリシーで少数に抑えられているため、ページングせず
/// 画面を開くたびに全件を取り直す。
final scheduledNotesProvider = FutureProvider.autoDispose<List<NoteDraftModel>>(
  (ref) async {
    final api = ref.watch(misskeyApiProvider);
    if (api == null) return const [];
    return api.getScheduledNotes();
  },
);
