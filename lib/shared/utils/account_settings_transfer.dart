import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account_model.dart';
import '../../data/models/app_settings_model.dart';
import '../providers/account_provider.dart';
import '../providers/account_tabs_provider.dart';
import '../providers/account_visibility_provider.dart';

/// 設定ファイルの `accountSettings` を組み立てる。
///
/// キーのアカウントIDは端末内でログインのたびに採番される UUID のため、
/// 別端末では一致しない。取り込み側で同一アカウントを特定できるよう
/// host / userId も併せて書き出す。
Map<String, dynamic> buildAccountSettingsForExport(WidgetRef ref) {
  return {
    for (final account in ref.read(accountProvider))
      account.id: {
        'host': account.host,
        'userId': account.userId,
        'tabs': ref
            .read(accountTabsProvider(account.id))
            .map((t) => t.toJson())
            .toList(),
        'defaultVisibility': ref.read(accountVisibilityProvider(account.id)),
      },
  };
}

/// 設定ファイルの `accountSettings` を端末内のアカウントに反映する。
///
/// [fileAccounts] はトークン付き設定（v3）に含まれるアカウント一覧。
/// host / userId を持たない旧形式の `accountSettings` でも、ここから
/// 同一アカウントを引けるようにするために受け取る。
///
/// [AccountNotifier.importAccounts] より前に呼ぶこと。アカウントが増えると
/// routerProvider が GoRouter を作り直し、呼び出し元の画面が破棄されて
/// 以降の ref.read が StateError になる（ログイン画面からの取り込みで
/// 2アカウント目以降の設定が反映されない不具合の原因だった）。
Future<void> applyImportedAccountSettings(
  WidgetRef ref,
  Map<String, dynamic> accountSettingsMap, {
  List<AccountModel> fileAccounts = const [],
}) async {
  final localAccounts = ref.read(accountProvider);
  final localIds = {for (final a in localAccounts) a.id};
  final fileAccountIds = {for (final a in fileAccounts) a.id};
  final fileAccountById = {for (final a in fileAccounts) a.id: a};

  for (final entry in accountSettingsMap.entries) {
    final data = entry.value as Map<String, dynamic>;
    final host = data['host'] as String? ?? fileAccountById[entry.key]?.host;
    final userId =
        data['userId'] as String? ?? fileAccountById[entry.key]?.userId;

    String? accountId;
    if (host != null && userId != null) {
      for (final a in localAccounts) {
        if (a.host == host && a.userId == userId) {
          accountId = a.id;
          break;
        }
      }
    }
    // 同一端末への書き戻し、またはこの後 importAccounts で追加されるアカウント。
    // どれにも当たらないものは、端末にいないアカウントの設定なので書き込まない
    // （書いても参照されない tabs_ / visibility_ キーが残るだけになる）。
    if (accountId == null &&
        (localIds.contains(entry.key) || fileAccountIds.contains(entry.key))) {
      accountId = entry.key;
    }
    if (accountId == null) continue;

    final tabsJson = data['tabs'] as List<dynamic>?;
    if (tabsJson != null) {
      final tabs = tabsJson
          .map((e) => TabConfigModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await ref.read(accountTabsProvider(accountId).notifier).setTabs(tabs);
    }

    final visibility = data['defaultVisibility'] as String?;
    if (visibility != null) {
      await ref
          .read(accountVisibilityProvider(accountId).notifier)
          .setVisibility(visibility);
    }
  }
}
