import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      theme: AppTheme.light.copyWith(
        textTheme: _applyFontScale(AppTheme.light.textTheme, factor),
      ),
      darkTheme: AppTheme.dark.copyWith(
        textTheme: _applyFontScale(AppTheme.dark.textTheme, factor),
      ),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
