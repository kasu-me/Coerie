import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/page_model.dart';
import 'pages_screen.dart';
import 'providers/pages_provider.dart';
import 'widgets/page_list_tile.dart';

/// 指定ユーザーのページ一覧（`/users/:userId/pages`）。
class UserPagesScreen extends ConsumerWidget {
  final String userId;

  /// AppBar のタイトルに使う表示名（未指定なら「ページ」のみ）。
  final String? userName;

  const UserPagesScreen({super.key, required this.userId, this.userName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userPagesProvider(userId));
    final notifier = ref.read(userPagesProvider(userId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(userName != null ? '$userName のページ' : 'ページ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: notifier.refresh,
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: PagedPagesList<PageModel>(
          state: state,
          rawError: notifier.lastError,
          errorFallback: 'ページの取得に失敗しました',
          onRefresh: notifier.refresh,
          onLoadMore: () => notifier.fetch(loadMore: true),
          itemBuilder: (page) => PageListTile(page: page),
          emptyBuilder: (onRefresh) => PagesEmptyView(
            title: 'ページがありません',
            description: 'このユーザーはページを公開していないか、\nサーバーがこの機能に対応していません',
            onRefresh: onRefresh,
          ),
        ),
      ),
    );
  }
}
