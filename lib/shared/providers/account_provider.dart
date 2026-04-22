import 'dart:async';

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
    final accounts = box.values.toList();

    // 複数のアカウントが isActive=true になっている場合は最初の1件だけ残す
    bool foundActive = false;
    final toFix = <AccountModel>[];
    for (final a in accounts) {
      if (a.isActive) {
        if (foundActive) {
          a.isActive = false;
          toFix.add(a);
        } else {
          foundActive = true;
        }
      }
    }

    state = accounts;

    // 不整合があった場合は非同期でディスクに保存
    if (toFix.isNotEmpty) {
      unawaited(_persistFix(toFix));
    }
  }

  Future<void> _persistFix(List<AccountModel> accounts) async {
    final box = HiveService.accountsBox;
    for (final a in accounts) {
      await box.put(a.id, a);
    }
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

  /// トークンを更新する（トークン失効・権限追加時の再取得に使用）
  Future<void> updateToken(String accountId, String newToken) async {
    final box = HiveService.accountsBox;
    final account = state.firstWhere((a) => a.id == accountId);
    final updated = AccountModel(
      id: account.id,
      host: account.host,
      token: newToken,
      userId: account.userId,
      username: account.username,
      name: account.name,
      avatarUrl: account.avatarUrl,
      isActive: account.isActive,
    );
    await box.put(accountId, updated);
    _load();
  }

  /// インポート用: 既存IDと重複しないアカウントのみ追加する（アクティブ状態は引き継がない）
  Future<void> importAccounts(List<AccountModel> accounts) async {
    final box = HiveService.accountsBox;
    final existingIds = {for (final a in state) a.id};
    for (final account in accounts) {
      if (!existingIds.contains(account.id)) {
        // インポート時は isActive をリセット（_load() の整合性チェックで保証）
        account.isActive = false;
        await box.put(account.id, account);
      }
    }
    // インポート後にアクティブアカウントが存在しない場合は先頭をアクティブに
    final allAccounts = box.values.toList();
    if (allAccounts.isNotEmpty && !allAccounts.any((a) => a.isActive)) {
      allAccounts.first.isActive = true;
      await box.put(allAccounts.first.id, allAccounts.first);
    }
    _load();
  }
}
