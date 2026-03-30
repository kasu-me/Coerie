import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/auth/miauth_service.dart';
import 'data/local/hive_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();

  // OOM Kill 後にディープリンク（coerie://auth）でアプリが再起動した場合、
  // getInitialLink() でそのURIを受け取り MiAuthService に渡す。
  final initialLink = await AppLinks().getInitialLink();
  if (initialLink != null) {
    MiAuthService.handleDeepLink(initialLink);
  }

  runApp(const ProviderScope(child: App()));
}
