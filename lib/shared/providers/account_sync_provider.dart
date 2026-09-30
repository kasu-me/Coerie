import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/remote/misskey_api.dart';
import 'account_provider.dart';

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
    final account = _ref.read(activeAccountProvider);
    if (account == null) return;
    // misskeyApiProvider を経由せず、同じ AccountModel からクライアントを作る。
    // 切替通知の中で misskeyApiProvider を読むと、Riverpod の通知順によっては
    // 切替前アカウントのクライアントが返り、別アカウントのプロフィールで
    // 上書きしてしまう（A→B→A と切り替えると A が B の表示になる不具合があった）。
    final api = MisskeyApi(host: account.host, token: account.token);
    try {
      final me = await api.getMe();
      // 応答待ちの間にアカウントが切り替えられた場合や、応答が別ユーザーの
      // ものだった場合に、無関係なアカウントの保存値を上書きしないための照合。
      if (me.id != account.userId) return;
      if (_ref.read(activeAccountProvider)?.id != account.id) return;
      await _ref
          .read(accountProvider.notifier)
          .syncProfile(
            account.id,
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
