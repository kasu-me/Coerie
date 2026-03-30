import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/account_model.dart';
import '../../data/local/hive_service.dart';

final accountProvider =
    StateNotifierProvider<AccountNotifier, List<AccountModel>>(
      (ref) => AccountNotifier(),
    );

final activeAccountProvider = Provider<AccountModel?>((ref) {
  final accounts = ref.watch(accountProvider);
  try {
    return accounts.firstWhere((a) => a.isActive);
  } catch (_) {
    return accounts.isNotEmpty ? accounts.first : null;
  }
});

class AccountNotifier extends StateNotifier<List<AccountModel>> {
  AccountNotifier() : super([]) {
    _load();
  }

  void _load() {
    final box = HiveService.accountsBox;
    state = box.values.toList();
  }

  Future<void> addAccount(AccountModel account) async {
    final box = HiveService.accountsBox;
    // 追加時は他のアカウントを非アクティブに
    for (final a in state) {
      a.isActive = false;
      await box.put(a.id, a);
    }
    account.isActive = true;
    await box.put(account.id, account);
    _load();
  }

  Future<void> switchAccount(String accountId) async {
    final box = HiveService.accountsBox;
    for (final a in state) {
      a.isActive = a.id == accountId;
      await box.put(a.id, a);
    }
    _load();
  }

  Future<void> removeAccount(String accountId) async {
    final box = HiveService.accountsBox;
    await box.delete(accountId);
    final remaining = box.values.toList();
    // 削除後にアクティブアカウントがなければ最初を選択
    if (remaining.isNotEmpty && !remaining.any((a) => a.isActive)) {
      remaining.first.isActive = true;
      await box.put(remaining.first.id, remaining.first);
    }
    _load();
  }
}
