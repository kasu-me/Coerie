import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'core/auth/miauth_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/account_model.dart';
import 'features/compose/emoji_picker_sheet.dart';
import 'shared/providers/account_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/is_locked_provider.dart';

/// 画面に紐付かない箇所からスナックバーを表示するためのキー
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  static const _channel = MethodChannel('coerie/share');
  AppLifecycleState? _previousLifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // isLockedProvider を早期初期化してキャッシュ値を即座に反映させる
    ref.read(isLockedProvider);

    // ブラウザ復帰時にアプリのプロセスが破棄されていた場合、
    // 起動時に受け取ったコールバックURIから認証を再開する
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumePendingAuth());

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// MiAuth のコールバックで起動された場合にトークン取得を完了させる。
  /// 認証を開始した画面（ログイン／アカウント設定）はプロセスごと消えているため、
  /// ここで既存アカウントの更新か新規追加かを判断して反映する。
  Future<void> _resumePendingAuth() async {
    if (!MiAuthService.hasPendingCallback) return;

    final result = await MiAuthService.tryResumeAuth();
    if (result == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('認証を完了できませんでした。もう一度お試しください')),
      );
      return;
    }

    final notifier = ref.read(accountProvider.notifier);
    AccountModel? existing;
    for (final a in ref.read(accountProvider)) {
      if (a.host == result.host && a.userId == result.user.id) {
        existing = a;
        break;
      }
    }

    if (existing != null) {
      await notifier.updateToken(existing.id, result.token);
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('トークンを更新しました')),
      );
    } else {
      await notifier.addAccount(
        AccountModel(
          id: const Uuid().v4(),
          host: result.host,
          token: result.token,
          userId: result.user.id,
          username: result.user.username,
          name: result.user.name,
          avatarUrl: result.user.avatarUrl,
          isActive: true,
        ),
      );
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${result.user.acct} でログインしました')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンドからの復帰時のみカスタム絵文字キャッシュを無効化する。
    // 初回起動時にも resumed が発火するため、直前の状態が paused/hidden の
    // 場合（= 本当のバックグラウンド復帰）に限定して invalidate する。
    if (state == AppLifecycleState.resumed &&
        (_previousLifecycleState == AppLifecycleState.paused ||
            _previousLifecycleState == AppLifecycleState.hidden)) {
      ref.invalidate(customEmojisProvider);
    }
    _previousLifecycleState = state;
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
      scaffoldMessengerKey: scaffoldMessengerKey,
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // フォントサイズ設定は TextScaler のみで適用する。
      // テーマの textTheme にも同時にスケールを掛けると二重適用（factor²）になるため
      // ここ以外でフォント倍率を掛けないこと。
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(factor)),
        child: child!,
      ),
    );
  }
}
