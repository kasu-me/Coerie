import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/settings_provider.dart';

/// fontSize が null のスタイルをスキップしてスケールを適用する。
/// TextTheme.apply(fontSizeFactor:) はfontSize==nullのスタイルに対して
/// アサーションエラーになるため、このヘルパーで安全に適用する。
TextTheme _applyFontScale(TextTheme base, double factor) {
  if (factor == 1.0) return base;
  TextStyle? scale(TextStyle? s) => (s != null && s.fontSize != null)
      ? s.copyWith(fontSize: s.fontSize! * factor)
      : s;
  return base.copyWith(
    displayLarge: scale(base.displayLarge),
    displayMedium: scale(base.displayMedium),
    displaySmall: scale(base.displaySmall),
    headlineLarge: scale(base.headlineLarge),
    headlineMedium: scale(base.headlineMedium),
    headlineSmall: scale(base.headlineSmall),
    titleLarge: scale(base.titleLarge),
    titleMedium: scale(base.titleMedium),
    titleSmall: scale(base.titleSmall),
    bodyLarge: scale(base.bodyLarge),
    bodyMedium: scale(base.bodyMedium),
    bodySmall: scale(base.bodySmall),
    labelLarge: scale(base.labelLarge),
    labelMedium: scale(base.labelMedium),
    labelSmall: scale(base.labelSmall),
  );
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  static const _channel = MethodChannel('coerie/share');

  @override
  void initState() {
    super.initState();

    // 初期起動時の共有データをAndroidネイティブから取得
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final data = await _channel.invokeMethod<Map>('getInitialSharedData');
        if (data != null) {
          final text = data['text'] as String?;
          final files = (data['files'] as List?)?.cast<String>();
          if (text != null && text.isNotEmpty) {
            ref
                .read(routerProvider)
                .push('/compose', extra: {'initialText': text});
          } else if (files != null && files.isNotEmpty) {
            final xfiles = files.map((p) => XFile(p)).toList();
            ref
                .read(routerProvider)
                .push('/compose', extra: {'initialLocalFiles': xfiles});
          }
        }
      } catch (_) {}
    });

    // ランタイムで共有が来たときにネイティブからのコールを受け取る
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onSharedText') {
          final text = call.arguments as String?;
          if (text != null && text.isNotEmpty) {
            ref
                .read(routerProvider)
                .push('/compose', extra: {'initialText': text});
          }
        } else if (call.method == 'onSharedFiles') {
          final files = (call.arguments as List?)?.cast<String>();
          if (files != null && files.isNotEmpty) {
            final xfiles = files.map((p) => XFile(p)).toList();
            ref
                .read(routerProvider)
                .push('/compose', extra: {'initialLocalFiles': xfiles});
          }
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final factor = settings.fontSize / 14.0;

    ThemeMode themeMode = switch (settings.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'Coerie',
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
      theme: AppTheme.light.copyWith(
        textTheme: _applyFontScale(AppTheme.light.textTheme, factor),
      ),
      darkTheme: AppTheme.dark.copyWith(
        textTheme: _applyFontScale(AppTheme.dark.textTheme, factor),
      ),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(factor)),
        child: child!,
      ),
    );
  }
}
