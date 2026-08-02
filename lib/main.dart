import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/auth/miauth_service.dart';
import 'data/local/hive_service.dart';
import 'features/startup/startup_error_screen.dart';
import 'shared/providers/shared_preferences_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  _registerBundledLicenses();
  await _startApp();
}

/// SharedPreferences の取得以降の起動処理。
/// 失敗時は起動エラー画面を表示し、再試行するとここへ戻ってくる。
Future<void> _startApp() async {
  final SharedPreferences prefs;
  try {
    prefs = await _loadPreferences();
  } catch (e, st) {
    debugPrint('SharedPreferences の読み込みに失敗しました: $e');
    debugPrintStack(stackTrace: st);
    runApp(StartupErrorApp(error: e, onRetry: _startApp));
    return;
  }

  // OOM Kill 後にディープリンク（coerie://auth）でアプリが再起動した場合、
  // getInitialLink() でそのURIを受け取り MiAuthService に渡す。
  try {
    final initialLink = await AppLinks().getInitialLink();
    if (initialLink != null) {
      MiAuthService.handleDeepLink(initialLink);
    }
  } catch (e, st) {
    // ディープリンクを1回取りこぼすだけなので起動は続行する。
    debugPrint('初期ディープリンクの取得に失敗しました: $e');
    debugPrintStack(stackTrace: st);
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}

/// 失敗時に1回だけ再試行する。
/// getInstance() は失敗すると内部キャッシュを破棄するため、再試行で再初期化される。
Future<SharedPreferences> _loadPreferences() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (e, st) {
    debugPrint('SharedPreferences の読み込みに失敗、再試行します: $e');
    debugPrintStack(stackTrace: st);
    return SharedPreferences.getInstance();
  }
}

void _registerBundledLicenses() {
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
}
