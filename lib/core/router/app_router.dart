import '../../data/models/drive_file_model.dart';
import '../../data/models/note_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../data/remote/misskey_api.dart';
import '../../features/auth/login_screen.dart';
import '../../features/clips/clips_screen.dart';
import '../../features/clips/clip_notes_screen.dart';
import '../../data/models/clip_model.dart';
import '../../features/favorites/favorites_screen.dart';
import '../../features/lists/lists_screen.dart';
import '../../features/antennas/antennas_screen.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../features/drive/drive_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/compose/compose_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../../features/draft/draft_screen.dart';
import '../../features/settings/appearance_settings_screen.dart';
import '../../features/settings/timeline_settings_screen.dart';
import '../../features/settings/image_posting_settings_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
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
import '../../features/channels/channels_screen.dart';
import '../../features/channels/channel_detail_screen.dart';
import '../../features/chat/chat_list_screen.dart';
import '../../features/chat/chat_thread_screen.dart';
import '../../features/pages/pages_screen.dart';
import '../../features/pages/page_view_screen.dart';
import '../../features/pages/page_editor_screen.dart';
import '../../features/pages/user_pages_screen.dart';
import '../../data/models/page_model.dart';
import '../../features/gallery/gallery_screen.dart';
import '../../features/gallery/gallery_detail_screen.dart';
import '../../features/gallery/gallery_form_screen.dart';
import '../../features/gallery/user_gallery_screen.dart';
import '../../data/models/gallery_post_model.dart';

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
          final initialChannelId = extra?['channelId'] as String?;
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
            initialChannelId: initialChannelId,
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
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(path: '/list', builder: (context, state) => const ListsScreen()),
      GoRoute(
        path: '/list/:listId',
        builder: (context, state) {
          final extra = state.extra;
          final listId = state.pathParameters['listId']!;
          if (extra is Map<String, dynamic>) {
            final name = extra['name'] as String? ?? 'リスト';
            return _SourceTimelineScreen(
              sourceId: listId,
              name: name,
              tabType: AppConstants.tabTypeList,
              timelinePrefix: 'list',
            );
          }
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
      // ---- ページ ----
      GoRoute(path: '/pages', builder: (context, state) => const PagesScreen()),
      // '/pages/new' は '/pages/:pageId' より前に置く。
      // go_router は宣言順にマッチするため、後ろだと 'new' が pageId として食われる。
      GoRoute(
        path: '/pages/new',
        builder: (context, state) => const PageEditorScreen(),
      ),
      GoRoute(
        path: '/pages/:pageId/edit',
        builder: (context, state) {
          final extra = state.extra;
          return PageEditorScreen(
            pageId: state.pathParameters['pageId']!,
            initialPage: extra is PageModel ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/pages/:pageId',
        builder: (context, state) {
          final extra = state.extra;
          return PageViewScreen(
            pageId: state.pathParameters['pageId']!,
            initialPage: extra is PageModel ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/users/:userId/pages',
        builder: (context, state) {
          final extra = state.extra;
          return UserPagesScreen(
            userId: state.pathParameters['userId']!,
            userName: extra is UserModel ? extra.name : null,
          );
        },
      ),

      // ---- ギャラリー ----
      GoRoute(
        path: '/gallery',
        builder: (context, state) => const GalleryScreen(),
      ),
      // '/gallery/new' は '/gallery/:postId' より前に置く（理由は /pages/new と同じ）
      GoRoute(
        path: '/gallery/new',
        builder: (context, state) => const GalleryFormScreen(),
      ),
      GoRoute(
        path: '/gallery/:postId/edit',
        builder: (context, state) {
          final extra = state.extra;
          return GalleryFormScreen(
            postId: state.pathParameters['postId']!,
            post: extra is GalleryPostModel ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/gallery/:postId',
        builder: (context, state) {
          final extra = state.extra;
          return GalleryDetailScreen(
            postId: state.pathParameters['postId']!,
            initialPost: extra is GalleryPostModel ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/users/:userId/gallery',
        builder: (context, state) {
          final extra = state.extra;
          return UserGalleryScreen(
            userId: state.pathParameters['userId']!,
            userName: extra is UserModel ? extra.name : null,
          );
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
          final antennaId = state.pathParameters['antennaId']!;
          if (extra is Map<String, dynamic>) {
            final name = extra['name'] as String? ?? 'アンテナ';
            return _SourceTimelineScreen(
              sourceId: antennaId,
              name: name,
              tabType: AppConstants.tabTypeAntenna,
              timelinePrefix: 'antenna',
            );
          }
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
          GoRoute(
            path: 'appearance',
            builder: (context, state) => const AppearanceSettingsScreen(),
          ),
          GoRoute(
            path: 'timeline',
            builder: (context, state) => const TimelineSettingsScreen(),
          ),
          GoRoute(
            path: 'image-posting',
            builder: (context, state) => const ImagePostingSettingsScreen(),
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationSettingsScreen(),
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
      GoRoute(
        path: '/channels',
        builder: (context, state) => const ChannelsScreen(),
      ),
      GoRoute(
        path: '/channels/:channelId',
        builder: (context, state) {
          final channelId = state.pathParameters['channelId']!;
          final extra = state.extra;
          final initialData = extra is Map<String, dynamic> ? extra : null;
          return ChannelDetailScreen(
            channelId: channelId,
            initialData: initialData,
          );
        },
      ),
      GoRoute(path: '/dm', builder: (context, state) => const ChatListScreen()),
      GoRoute(
        path: '/dm/user/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final extra = state.extra as Map<String, dynamic>?;
          final name = extra?['name'] as String? ?? 'DM';
          final avatarUrl = extra?['avatarUrl'] as String?;
          return ChatThreadScreen(
            userId: userId,
            partnerName: name,
            partnerAvatarUrl: avatarUrl,
          );
        },
      ),
      GoRoute(
        path: '/dm/room/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId']!;
          final extra = state.extra as Map<String, dynamic>?;
          final name = extra?['name'] as String? ?? 'グループ';
          return ChatThreadScreen(roomId: roomId, partnerName: name);
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
        return _SourceTimelineScreen(
          sourceId: listId,
          name: title,
          tabType: AppConstants.tabTypeList,
          timelinePrefix: 'list',
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
        return _SourceTimelineScreen(
          sourceId: antennaId,
          name: title,
          tabType: AppConstants.tabTypeAntenna,
          timelinePrefix: 'antenna',
        );
      },
    );
  }
}

// ─── List/Antenna timeline screen with "add to home tab" menu ───────────────

/// リスト・アンテナ共通の「ホームタブに追加」メニュー付きタイムライン画面。
/// [timelinePrefix] は timelineType の接頭辞（'list' / 'antenna'）、
/// [tabType] はタブ設定に保存する種別（AppConstants.tabTypeList など）。
class _SourceTimelineScreen extends ConsumerStatefulWidget {
  final String sourceId;
  final String name;
  final String tabType;
  final String timelinePrefix;
  const _SourceTimelineScreen({
    required this.sourceId,
    required this.name,
    required this.tabType,
    required this.timelinePrefix,
  });

  @override
  ConsumerState<_SourceTimelineScreen> createState() =>
      _SourceTimelineScreenState();
}

class _SourceTimelineScreenState extends ConsumerState<_SourceTimelineScreen> {
  Future<void> _addToHomeTab() async {
    final labelController = TextEditingController(text: widget.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ホームタブに追加'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: 'タブ名',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    final input = labelController.text.trim();
    labelController.dispose();
    if (confirmed != true || !mounted) return;
    final label = input.isEmpty ? widget.name : input;
    final accountId = ref.read(activeAccountProvider)?.id ?? '';
    final currentTabs = List<TabConfigModel>.from(
      ref.read(accountTabsProvider(accountId)),
    );
    currentTabs.add(
      TabConfigModel(
        id: const Uuid().v4(),
        label: label,
        type: widget.tabType,
        sourceId: widget.sourceId,
      ),
    );
    await ref
        .read(accountTabsProvider(accountId).notifier)
        .setTabs(currentTabs);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「$label」タブを追加しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_tab') _addToHomeTab();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_tab',
                child: Row(
                  children: [
                    Icon(Icons.add_to_photos_outlined),
                    SizedBox(width: 8),
                    Text('ホームタブに追加'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TimelineScreen(
        timelineType: '${widget.timelinePrefix}:${widget.sourceId}',
      ),
    );
  }
}
