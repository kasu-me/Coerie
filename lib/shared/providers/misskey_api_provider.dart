import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/remote/misskey_api.dart';
import '../providers/account_provider.dart';

final misskeyApiProvider = Provider<MisskeyApi?>((ref) {
  final account = ref.watch(activeAccountProvider);
  if (account == null) return null;
  return MisskeyApi(host: account.host, token: account.token);
});
