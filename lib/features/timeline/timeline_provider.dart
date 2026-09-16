import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/note_model.dart';
import '../../data/models/app_settings_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/api_error_message.dart';
import '../../core/streaming/streaming_service.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/account_tabs_provider.dart';
import '../../shared/providers/notifications_badge_provider.dart';
import '../../shared/providers/word_mute_provider.dart';

/// 原因を特定できなかった取得失敗の表示文言。
const String _timelineErrorFallback = 'タイムラインを取得できませんでした';

class TimelineState {
  final List<NoteModel> notes;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const TimelineState({
    this.notes = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  TimelineState copyWith({
    List<NoteModel>? notes,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) => TimelineState(
    notes: notes ?? this.notes,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: error,
  );
}

final timelineProvider =
    StateNotifierProviderFamily<TimelineNotifier, TimelineState, String>(
      (ref, timelineType) => TimelineNotifier(ref, timelineType),
    );

class TimelineNotifier extends StateNotifier<TimelineState> {
  final Ref _ref;
  final String timelineType;
  StreamSubscription<NoteUpdateEvent>? _noteUpdateSub;

  /// メモリ上に保持するノートの最大件数。
  /// ストリーミングで先頭に追加され続けると無制限に増え、受信ごとの
  /// O(n) コピー/重複チェックが重くなって UI スレッドが飽和する。
  /// 古い末尾を切り捨てることで増加を抑える。
  static const int _maxNotes = 500;

  /// 取得済みで最も古い／新しいノートのID（ワードミュートで除外したぶんも含む）。
  ///
  /// カーソルに state.notes の端を使うと、取得した1ページが丸ごとミュートされた
  /// ときに untilId／sinceId が進まず、同じページを取り続けて追加読み込みが
  /// 空回りする。除外前の取得結果からカーソルを控えておく。
  String? _oldestFetchedId;
  String? _newestFetchedId;

  /// ページングで読み込んだ件数。上限はこれを下回らない。
  ///
  /// 追加読み込みしたぶんまで [_maxNotes] で切ると、追加した20件がその場で
  /// 捨てられて untilId（末尾のノートID）が進まず、以降スクロールのたびに
  /// 同じページを取得し続けて追加読み込みが空回りする。
  int _pagedCount = 0;

  /// 実際に適用する上限。ページングで読み込んだぶんは切り捨てない。
  int get _noteLimit => _pagedCount > _maxNotes ? _pagedCount : _maxNotes;

  /// ノートリストが上限を超えていれば古い末尾を切り捨てる。
  ///
  /// 切り捨てが起きるのはストリーミング受信で先頭に積まれた場合だけで、
  /// その経路は画面が最上部にあるときしか呼ばれない（timeline_screen 参照）。
  /// つまり切り落とすのは常に画面外の末尾側になる。
  List<NoteModel> _capNotes(List<NoteModel> notes) {
    final limit = _noteLimit;
    if (notes.length <= limit) return notes;
    return notes.sublist(0, limit);
  }

  TimelineNotifier(this._ref, this.timelineType)
    : super(const TimelineState()) {
    fetchNotes();
    // アカウント切り替え時にTLをリセット＆再取得
    _ref.listen(activeAccountProvider, (prev, next) {
      if (prev?.id != next?.id) {
        // isLoading: true で即座にローディング表示に切り替える
        _noteIds.clear();
        _pagedCount = 0;
        _oldestFetchedId = null;
        _newestFetchedId = null;
        state = const TimelineState(isLoading: true);
        // アカウント切り替え時は各タイムラインを再取得する。
        // microtask で遅延させることで misskeyApiProvider が新アカウントで
        // 再計算されてから fetch が実行されることを保証する
        Future.microtask(() => fetchNotes());
      }
    });
    // ワードミュート設定はサーバーから非同期で届くため、最初の取得に間に合わない
    // ことがある。届いた時点・変更された時点で保持中のノートへ適用し直す。
    // 解除された場合に消したノートは戻らないが、再読み込みで復帰する。
    _ref.listen(wordMuteFilterProvider, (prev, next) {
      if (next.isEmpty || state.notes.isEmpty) return;
      final visible = next.apply(state.notes);
      if (visible.length != state.notes.length) {
        state = state.copyWith(notes: _syncNotes(visible));
      }
    });
    // ストリーミングサービスの削除イベントを購読
    _subscribeNoteUpdates(_ref.read(streamingServiceProvider));
    _ref.listen<StreamingService?>(streamingServiceProvider, (prev, next) {
      _noteUpdateSub?.cancel();
      _subscribeNoteUpdates(next);
    });
  }

  void _subscribeNoteUpdates(StreamingService? streaming) {
    if (streaming == null) return;
    _noteUpdateSub = streaming.noteUpdateStream.listen((event) {
      if (event.type == 'deleted') {
        removeNote(event.noteId);
      }
    });
  }

  @override
  void dispose() {
    _noteUpdateSub?.cancel();
    super.dispose();
  }

  String getEndpoint(String type) {
    if (type.startsWith('list:')) return 'notes/user-list-timeline';
    if (type.startsWith('antenna:')) return 'antennas/notes';
    if (type.startsWith('channel:')) return 'channels/timeline';
    return switch (type) {
      AppConstants.tabTypeHome => 'notes/timeline',
      AppConstants.tabTypeLocal => 'notes/local-timeline',
      AppConstants.tabTypeSocial => 'notes/hybrid-timeline',
      AppConstants.tabTypeGlobal => 'notes/global-timeline',
      _ => 'notes/timeline',
    };
  }

  Map<String, dynamic> getExtraParams(String type) {
    final tab = _findTabConfig(type);
    final params = <String, dynamic>{};

    if (type.startsWith('list:')) {
      params['listId'] = type.substring(5);
    } else if (type.startsWith('antenna:')) {
      return {'antennaId': type.substring(8)};
    } else if (type.startsWith('channel:')) {
      return {'channelId': type.substring(8)};
    }

    // withReplies: ローカルTL・ソーシャルTLのみ対応
    if (type == AppConstants.tabTypeLocal ||
        type == AppConstants.tabTypeSocial) {
      if (tab?.withReplies != null) {
        params['withReplies'] = tab!.withReplies;
      }
    }

    // withRenotes: ホーム/ローカル/ソーシャル/グローバル/リストTLに対応
    if (type == AppConstants.tabTypeHome ||
        type == AppConstants.tabTypeLocal ||
        type == AppConstants.tabTypeSocial ||
        type == AppConstants.tabTypeGlobal ||
        type.startsWith('list:')) {
      if (tab?.withRenotes != null) {
        params['withRenotes'] = tab!.withRenotes;
      }
    }

    // withFiles: ホーム/ローカル/ソーシャル/グローバル/リストTLに対応
    if (type == AppConstants.tabTypeHome ||
        type == AppConstants.tabTypeLocal ||
        type == AppConstants.tabTypeSocial ||
        type == AppConstants.tabTypeGlobal ||
        type.startsWith('list:')) {
      if (tab?.withFiles != null) {
        params['withFiles'] = tab!.withFiles;
      }
    }

    return params;
  }

  /// timelineTypeに対応するTabConfigModelを検索する
  TabConfigModel? _findTabConfig(String type) {
    final accountId = _ref.read(activeAccountProvider)?.id ?? '';
    if (accountId.isEmpty) return null;
    final tabs = _ref.read(accountTabsProvider(accountId));
    for (final tab in tabs) {
      if (type.startsWith('list:') && tab.type == AppConstants.tabTypeList) {
        if (tab.sourceId == type.substring(5)) return tab;
      } else if (type.startsWith('antenna:') &&
          tab.type == AppConstants.tabTypeAntenna) {
        if (tab.sourceId == type.substring(8)) return tab;
      } else if (type.startsWith('channel:') &&
          tab.type == AppConstants.tabTypeChannel) {
        if (tab.sourceId == type.substring(8)) return tab;
      } else if (tab.type == type) {
        return tab;
      }
    }
    return null;
  }

  Future<void> fetchNotes({bool loadMore = false}) async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) {
      state = state.copyWith(isLoading: false, error: 'ログインが必要です');
      return;
    }

    if (loadMore) {
      if (state.isLoadingMore) return;
      state = state.copyWith(isLoadingMore: true, error: null);
    } else {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final endpoint = getEndpoint(timelineType);
      final extraParams = getExtraParams(timelineType);
      final untilId = loadMore ? _oldestFetchedId : null;
      final notes = await api.getTimeline(
        endpoint: endpoint,
        limit: 20,
        untilId: untilId,
        extraParams: extraParams,
      );
      _updateCursors(notes, keepNewest: loadMore);
      final visible = _filterMuted(notes);

      if (loadMore) {
        state = state.copyWith(
          isLoadingMore: false,
          notes: _syncNotes([...state.notes, ...visible], paged: true),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          notes: _syncNotes(visible, paged: true),
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: apiErrorMessage(e, fallback: _timelineErrorFallback),
      );
    }
  }

  Future<void> refresh() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) return;

    // isLoading を立てずにリフレッシュすることで、リスト表示を維持したまま
    // スクロール位置・ScrollController のアタッチ状態を壊さない。
    // isLoadingMore を一時的に使って二重実行を防ぐ。
    if (state.isLoading || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true, error: null);

    try {
      final endpoint = getEndpoint(timelineType);
      final extraParams = getExtraParams(timelineType);
      final notes = await api.getTimeline(
        endpoint: endpoint,
        limit: 20,
        extraParams: extraParams,
      );
      _updateCursors(notes);
      state = state.copyWith(
        isLoadingMore: false,
        notes: _syncNotes(_filterMuted(notes), paged: true),
      );
      // WebSocket が接続されていない場合は、通知を API から手動取得してバッジ等を更新する
      final status = _ref
          .read(streamingStatusProvider)
          .maybeWhen(data: (s) => s, orElse: () => null);
      if (status == null || status != StreamingStatus.connected) {
        final account = _ref.read(activeAccountProvider);
        if (account != null) {
          try {
            await _ref
                .read(notificationsBadgeProvider(account.id).notifier)
                .refreshFromApi();
          } catch (_) {}
        }
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: apiErrorMessage(e, fallback: _timelineErrorFallback),
      );
    }
  }

  /// 保持中のノートIDの集合。ストリーミング受信ごとの重複チェックを
  /// リスト全走査（O(n)）にしないために state と同期して保持する。
  final Set<String> _noteIds = {};

  /// 上限を適用したうえで [_noteIds] を同期し、state に入れるリストを返す。
  /// state の更新は呼び出し側で1回だけ行うこと（分けると余分な再構築が起きる）。
  ///
  /// [paged] は取得・追加読み込みの経路から呼ぶ場合に true にする。
  /// 渡された件数を切り捨て下限として記録し、読み込んだぶんが失われないようにする。
  List<NoteModel> _syncNotes(List<NoteModel> notes, {bool paged = false}) {
    if (paged) _pagedCount = notes.length;
    final capped = _capNotes(notes);
    _noteIds
      ..clear()
      ..addAll(capped.map((n) => n.id));
    return capped;
  }

  /// ワードミュートに一致するノートを取り除く。
  List<NoteModel> _filterMuted(List<NoteModel> notes) =>
      _ref.read(wordMuteFilterProvider).apply(notes);

  /// 取得結果（ミュートで除外する前）からページングのカーソルを進める。
  ///
  /// [keepNewest] が true の場合は追加読み込み＝より古い方向への取得なので、
  /// 新着取得用のカーソルは触らない。
  void _updateCursors(List<NoteModel> fetched, {bool keepNewest = false}) {
    if (fetched.isEmpty) return;
    _oldestFetchedId = fetched.last.id;
    if (!keepNewest) _newestFetchedId = fetched.first.id;
  }

  /// 新着カーソルを [id] まで進める（既存より新しい場合のみ）。
  void _advanceNewestCursor(String id) {
    final current = _newestFetchedId;
    if (current == null || id.compareTo(current) > 0) _newestFetchedId = id;
  }

  void prependNote(NoteModel note) {
    if (_noteIds.contains(note.id)) return;
    _advanceNewestCursor(note.id);
    state = state.copyWith(notes: _syncNotes([note, ...state.notes]));
  }

  Future<List<NoteModel>> fetchNew() async {
    final api = _ref.read(misskeyApiProvider);
    // ミュートで表示中のノートが1件も無い状態でも、取得済みのカーソルがあれば
    // 続きを取りに行ける。
    final sinceId =
        _newestFetchedId ??
        (state.notes.isNotEmpty ? state.notes.first.id : null);
    if (api == null || sinceId == null) return [];

    try {
      final endpoint = getEndpoint(timelineType);
      final extraParams = getExtraParams(timelineType);
      final newNotes = await api.getTimeline(
        endpoint: endpoint,
        limit: 20,
        sinceId: sinceId,
        extraParams: extraParams,
      );
      if (newNotes.isNotEmpty) {
        // sinceId 指定では昇順（古い順）で返るため、末尾が最新。
        _advanceNewestCursor(newNotes.last.id);
        // WebSocket の prependNote と競合した場合の重複を除去
        // sinceId を使うと Misskey API は昇順（古い順）でノートを返すため、
        // 降順（新しい順）に並べ替えてから先頭に挿入する
        final unique =
            _filterMuted(
                newNotes,
              ).where((n) => !_noteIds.contains(n.id)).toList()
              ..sort((a, b) => b.id.compareTo(a.id));
        // refresh() と競合した場合、unique に現在の先頭より古いノートが
        // 含まれていると順番が乱れるため、現在の先頭より新しいものだけ挿入する
        final currentTopId = state.notes.isNotEmpty
            ? state.notes.first.id
            : null;
        final toInsert = currentTopId == null
            ? unique
            : unique.where((n) => n.id.compareTo(currentTopId) > 0).toList();
        if (toInsert.isNotEmpty) {
          state = state.copyWith(
            notes: _syncNotes([...toInsert, ...state.notes]),
          );
        }
      }
      return newNotes;
    } catch (_) {
      return [];
    }
  }

  void removeNote(String noteId) {
    // 保持していないノートの削除イベントでは state を差し替えない
    // （全タイムラインが購読しているため、無関係な再構築を避ける）
    if (!_noteIds.contains(noteId)) return;
    state = state.copyWith(
      notes: _syncNotes(state.notes.where((n) => n.id != noteId).toList()),
    );
  }
}
