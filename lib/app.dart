import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/settings_provider.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    ThemeMode themeMode = switch (settings.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'Coerie',
      theme: AppTheme.light.copyWith(
        textTheme: AppTheme.light.textTheme.apply(
          fontSizeFactor: settings.fontSize / 14.0,
        ),
      ),
      darkTheme: AppTheme.dark.copyWith(
        textTheme: AppTheme.dark.textTheme.apply(
          fontSizeFactor: settings.fontSize / 14.0,
        ),
      ),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
