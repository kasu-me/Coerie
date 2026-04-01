import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/auth/miauth_service.dart';
import 'data/local/hive_service.dart';
import 'shared/providers/shared_preferences_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  final prefs = await SharedPreferences.getInstance();

  // OOM Kill 後にディープリンク（coerie://auth）でアプリが再起動した場合、
  // getInitialLink() でそのURIを受け取り MiAuthService に渡す。
  final initialLink = await AppLinks().getInitialLink();
  if (initialLink != null) {
    MiAuthService.handleDeepLink(initialLink);
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}
