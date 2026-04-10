import '../../data/models/note_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/account_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/clips/clips_screen.dart';
import '../../features/clips/clip_notes_screen.dart';
import '../../data/models/clip_model.dart';
import '../../features/drive/drive_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/compose/compose_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../../features/draft/draft_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/tabs_settings_screen.dart';
import '../../features/settings/mute_block_screen.dart';
import '../../features/settings/account_settings_screen.dart';
import '../../features/settings/app_info_screen.dart';
import '../../features/settings/privacy_policy_screen.dart';
import '../../features/notifications/notification_screen.dart';
import '../../features/notifications/announcements_screen.dart';
import '../../data/models/announcement_model.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/timeline/note_detail_screen.dart';
import '../../features/search/search_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final accountState = ref.watch(accountProvider);

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final isLoggedIn = accountState.isNotEmpty;
      final isLoginRoute = state.matchedLocation == '/login';
      final isAddingAccount = state.uri.queryParameters['addAccount'] == 'true';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      // アカウント追加モードのときはログイン済みでも /login を許可する
      if (isLoggedIn && isLoginRoute && !isAddingAccount) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final addAccount = state.uri.queryParameters['addAccount'] == 'true';
          return LoginScreen(addAccount: addAccount);
        },
      ),
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
          final initialLocalFiles = extra?['initialLocalFiles'] as List<XFile>?;
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
            initialLocalFiles: initialLocalFiles,
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
      GoRoute(path: '/clips', builder: (context, state) => const ClipsScreen()),
      GoRoute(
        path: '/clips/:clipId',
        builder: (context, state) {
          final clip = state.extra as ClipModel;
          return ClipNotesScreen(clip: clip);
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
        path: '/account-settings',
        builder: (context, state) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: '/app-info',
        builder: (context, state) => const AppInfoScreen(),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationScreen(),
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => const AnnouncementsScreen(),
      ),
      GoRoute(
        path: '/announcement/:id',
        builder: (context, state) {
          final ann = state.extra as AnnouncementModel;
          return AnnouncementDetailScreen(announcement: ann);
        },
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
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final initialTab = extra?['tab'] as int? ?? 0;
          final initialQuery = extra?['query'] as String?;
          return SearchScreen(
            initialTab: initialTab,
            initialQuery: initialQuery,
          );
        },
      ),
    ],
  );
});
