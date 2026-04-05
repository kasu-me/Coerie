import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  // Register bundled license texts so they appear in Flutter's license page.
  LicenseRegistry.addLicense(() async* {
    try {
      final noto = await rootBundle.loadString(
        'assets/licenses/noto-sans-jp-OFL.txt',
      );
      yield LicenseEntryWithLineBreaks(['Noto Sans JP'], noto);
    } catch (_) {}
    try {
      final twemoji = await rootBundle.loadString(
        'assets/licenses/twemoji-cc-by-4.0.txt',
      );
      yield LicenseEntryWithLineBreaks(['Twemoji (graphics)'], twemoji);
    } catch (_) {}
    try {
      final twmit = await rootBundle.loadString(
        'assets/licenses/twemoji-mit.txt',
      );
      yield LicenseEntryWithLineBreaks(['Twemoji (code)'], twmit);
    } catch (_) {}
    try {
      final gf = await rootBundle.loadString(
        'assets/licenses/google_fonts-BSD-3-Clause.txt',
      );
      yield LicenseEntryWithLineBreaks(['google_fonts package'], gf);
    } catch (_) {}
  });

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}
