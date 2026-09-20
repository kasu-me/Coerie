import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'account_provider.dart';
import 'misskey_api_provider.dart';

/// アクティブアカウントのプロフィール情報（表示名・ユーザー名・アイコン）を
/// サーバーの値へ追随させるサービス。
///
/// ドロワーやアカウント設定の表示名は、ログイン時に保存した AccountModel を
/// 参照している。そのため Misskey 側で名前を変えても再ログインするまで古い
/// ままになる。表示のたびに API を叩くのは無駄なので、値が変わり得る
/// タイミングでのみ取得し直す。
class AccountSyncService {
  final Ref _ref;

  AccountSyncService(this._ref) {
    unawaited(sync());
    _ref.listen<String?>(activeAccountProvider.select((a) => a?.id), (
      prev,
      next,
    ) {
      if (next != null && prev != next) {
        unawaited(sync());
      }
    });
  }

  Future<void> sync() async {
    final accountId = _ref.read(activeAccountProvider)?.id;
    final api = _ref.read(misskeyApiProvider);
    if (accountId == null || api == null) return;
    try {
      final me = await api.getMe();
      await _ref
          .read(accountProvider.notifier)
          .syncProfile(
            accountId,
            username: me.username,
            name: me.name,
            avatarUrl: me.avatarUrl,
          );
    } catch (_) {
      // ネットワークエラー等では保存済みの値をそのまま維持する
    }
  }
}

/// アカウント切替の監視を続ける必要があるため、アプリの生存期間中は破棄しない。
final accountSyncProvider = Provider<AccountSyncService>(
  (ref) => AccountSyncService(ref),
);
