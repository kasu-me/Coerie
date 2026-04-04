import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/app_constants.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  // version is loaded from platform info (pubspec) at runtime
  static const _author = 'M_Kasumi';
  static const _githubUrl = 'https://github.com/kasu-me/Coerie/tree/main';

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('URLを開けませんでした: $url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アプリ情報')),
      body: ListView(
        children: [
          const SizedBox(height: 32),
          // アプリアイコン + 名前
          Center(
            child: Column(
              children: [
                Image.asset(
                  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final versionText = snapshot.hasData
                        ? '${snapshot.data!.version}'
                        : '読み込み中';
                    return Text(
                      'バージョン $versionText',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('作者'),
            trailing: Text(
              _author,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub'),
            subtitle: const Text(_githubUrl),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _launchUrl(context, _githubUrl),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy-policy'),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
