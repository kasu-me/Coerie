import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_model.dart';
import 'user_avatar.dart';

/// ユーザー一覧を表示するボトムシート。
///
/// 「リアクションしたユーザー」「リノートしたユーザー」で、ヘッダー以外は
/// 完全に同じ100行が二重に書かれていたため共通化した。
///
/// [usersFuture] は **シートを開く前に1度だけ生成すること。** ビルダーの中で
/// 作ると、リビルドのたびに新しいリクエストが飛ぶ。
Future<void> showUserListSheet(
  BuildContext context, {

  /// ヘッダーの見出し。アイコンや絵文字を添えるため Widget で受ける。
  required Widget title,
  required Future<List<UserModel>> usersFuture,
  required String emptyMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(child: title),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
            FutureBuilder<List<UserModel>>(
              future: usersFuture,
              builder: (_, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final users = snapshot.data ?? const <UserModel>[];
                if (users.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(emptyMessage),
                  );
                }
                return SizedBox(
                  height: 320,
                  child: ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final user = users[index];
                      return UserListTile(
                        user: user,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          context.push('/profile/${user.id}');
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// ユーザー1件の行。アバター・表示名・acct を並べる。
class UserListTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onTap;

  const UserListTile({super.key, required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: UserAvatar(avatarUrl: user.avatarUrl, iconSize: 20),
      // 表示名が空のときのフォールバックは displayName に一本化している。
      title: Text(user.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(user.acct, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
