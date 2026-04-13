import '../../data/models/note_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../data/remote/misskey_api.dart';
import '../../features/auth/login_screen.dart';
import '../../features/clips/clips_screen.dart';
import '../../features/clips/clip_notes_screen.dart';
import '../../data/models/clip_model.dart';
import '../../features/lists/lists_screen.dart';
import '../../features/antennas/antennas_screen.dart';
import '../../features/timeline/timeline_screen.dart';
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
import '../../data/models/user_model.dart';
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
          final renoteId = extra?['renoteId'] as String?;
          final renoteToNote = extra?['renoteToNote'] as NoteModel?;
          return ComposeScreen(
            draftId: draftId,
            replyId: replyId,
            replyToNote: replyToNote,
            renoteId: renoteId,
            renoteToNote: renoteToNote,
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
      GoRoute(path: '/list', builder: (context, state) => const ListsScreen()),
      GoRoute(
        path: '/list/:listId',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            final listId = state.pathParameters['listId']!;
            final name = extra['name'] as String? ?? 'リスト';
            return Scaffold(
              appBar: AppBar(title: Text(name)),
              body: TimelineScreen(timelineType: 'list:$listId'),
            );
          }
          final listId = state.pathParameters['listId']!;
          return _ListLoader(listId: listId);
        },
      ),
      GoRoute(
        path: '/clips/:clipId',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ClipModel) return ClipNotesScreen(clip: extra);
          final clipId = state.pathParameters['clipId']!;
          final host = state.uri.queryParameters['host'];
          return _ClipLoader(clipId: clipId, host: host);
        },
      ),
      GoRoute(
        path: '/users/:userId/clips',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          String? userName;
          final extra = state.extra;
          if (extra is UserModel) userName = extra.name;
          return ClipsScreen(ownerUserId: userId, ownerUserName: userName);
        },
      ),
      GoRoute(
        path: '/antenna',
        builder: (context, state) => const AntennasScreen(),
      ),
      GoRoute(
        path: '/antenna/:antennaId',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            final antennaId = state.pathParameters['antennaId']!;
            final name = extra['name'] as String? ?? 'アンテナ';
            return Scaffold(
              appBar: AppBar(title: Text(name)),
              body: TimelineScreen(timelineType: 'antenna:$antennaId'),
            );
          }
          final antennaId = state.pathParameters['antennaId']!;
          return _AntennaLoader(antennaId: antennaId);
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

class _ClipLoader extends ConsumerWidget {
  final String clipId;
  final String? host;
  const _ClipLoader({required this.clipId, this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MisskeyApi? api = (host != null && host!.isNotEmpty)
        ? MisskeyApi(host: host!)
        : ref.read(misskeyApiProvider);

    if (api == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('読み込むにはアカウントが必要です')),
      );
    }

    return FutureBuilder<ClipModel>(
      future: api.getClip(clipId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('クリップの読み込みに失敗しました: ${snapshot.error}')),
          );
        }
        final clip = snapshot.data!;
        return ClipNotesScreen(clip: clip, host: host);
      },
    );
  }
}

class _ListLoader extends ConsumerWidget {
  final String listId;
  const _ListLoader({required this.listId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MisskeyApi? api = ref.read(misskeyApiProvider);

    if (api == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('読み込むにはアカウントが必要です')),
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: () async {
        final lists = await api.getLists();
        Map<String, dynamic>? found;
        for (final m in lists) {
          if ((m['id'] as String?) == listId) {
            found = m;
            break;
          }
        }
        return found;
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('リストの読み込みに失敗しました: ${snapshot.error}')),
          );
        }
        final item = snapshot.data;
        final title = item?['name'] as String? ?? 'リスト';
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: TimelineScreen(timelineType: 'list:$listId'),
        );
      },
    );
  }
}

class _AntennaLoader extends ConsumerWidget {
  final String antennaId;
  const _AntennaLoader({required this.antennaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MisskeyApi? api = ref.read(misskeyApiProvider);

    if (api == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('読み込むにはアカウントが必要です')),
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: () async {
        final items = await api.getAntennas();
        Map<String, dynamic>? found;
        for (final m in items) {
          if ((m['id'] as String?) == antennaId) {
            found = m;
            break;
          }
        }
        return found;
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('アンテナの読み込みに失敗しました: ${snapshot.error}')),
          );
        }
        final item = snapshot.data;
        final title = item?['name'] as String? ?? 'アンテナ';
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: TimelineScreen(timelineType: 'antenna:$antennaId'),
        );
      },
    );
  }
}
