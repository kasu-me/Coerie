import '../../data/models/note_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/account_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/drive/drive_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/compose/compose_screen.dart';
import '../../features/draft/draft_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/tabs_settings_screen.dart';
import '../../features/settings/mute_block_screen.dart';
import '../../features/notifications/notification_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/timeline/note_detail_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final accountState = ref.watch(accountProvider);

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final isLoggedIn = accountState.isNotEmpty;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/compose',
        builder: (context, state) {
          final draftId = state.uri.queryParameters['draftId'];
          final extra = state.extra as Map<String, dynamic>?;
          final replyId = extra?['replyId'] as String?;
          final replyToNote = extra?['replyToNote'] as NoteModel?;
          final initialText = extra?['initialText'] as String?;
          final initialVisibility = extra?['visibility'] as String?;
          final initialFiles = extra?['initialFiles'] as List<DriveFileModel>?;
          final initialCw = extra?['initialCw'] as String?;
          final initialIsSensitive =
              extra?['initialIsSensitive'] as bool? ?? false;
          return ComposeScreen(
            draftId: draftId,
            replyId: replyId,
            replyToNote: replyToNote,
            initialText: initialText,
            initialVisibility: initialVisibility,
            initialFiles: initialFiles,
            initialCw: initialCw,
            initialIsSensitive: initialIsSensitive,
          );
        },
      ),
      GoRoute(
        path: '/drafts',
        builder: (context, state) => const DraftScreen(),
      ),
      GoRoute(
        path: '/drive',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final selectionMode = extra?['selectionMode'] as bool? ?? false;
          final maxSelection = extra?['maxSelection'] as int? ?? 4;
          return DriveScreen(
            selectionMode: selectionMode,
            maxSelection: maxSelection,
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'tabs',
            builder: (context, state) => const TabsSettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/mute-block',
        builder: (context, state) => const MuteBlockScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationScreen(),
      ),
      GoRoute(
        path: '/profile/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileScreen(userId: userId);
        },
      ),
      GoRoute(
        path: '/note/:noteId',
        builder: (context, state) {
          final note = state.extra as NoteModel;
          return NoteDetailScreen(note: note);
        },
      ),
    ],
  );
});
