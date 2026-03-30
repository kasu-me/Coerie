import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfileScreen extends ConsumerWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: ユーザー情報をAPIから取得して表示
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_circle, size: 64),
            SizedBox(height: 16),
            Text('プロフィール画面は今後実装予定です'),
          ],
        ),
      ),
    );
  }
}
