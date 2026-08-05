import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/remote/misskey_api.dart';
import '../providers/account_provider.dart';

final misskeyApiProvider = Provider<MisskeyApi?>((ref) {
  final account = ref.watch(activeAccountProvider);
  if (account == null) return null;
  return MisskeyApi(host: account.host, token: account.token);
});

/// 他インスタンスを参照するための未認証APIクライアント。
///
/// ページ・ギャラリーは連合しないため、リモートのURLを開くには
/// そのホストのAPIを直接叩く必要がある。ホストごとに1つだけ生成される。
final remoteMisskeyApiProvider = Provider.family<MisskeyApi, String>(
  (ref, host) => MisskeyApi(host: host),
);

extension MisskeyApiHostRef on WidgetRef {
  /// [host] 上のリソースを読むためのAPIクライアントを返す。
  ///
  /// [host] が未指定、またはアクティブアカウントと同じホストなら認証済み
  /// クライアント。異なるホストならそのホストの未認証クライアントを返す。
  MisskeyApi? apiForHost(String? host) {
    if (!isRemoteHost(host)) return read(misskeyApiProvider);
    return read(remoteMisskeyApiProvider(host!));
  }

  /// [host] がアクティブアカウントとは別のインスタンスかどうか。
  ///
  /// true のときは未認証アクセスになるため、いいね・編集・削除といった
  /// 認証が要る操作は出さないこと。
  bool isRemoteHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return host != read(activeAccountProvider)?.host;
  }
}
