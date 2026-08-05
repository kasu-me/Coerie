import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streaming/streaming_service.dart';
import '../../data/remote/misskey_api.dart';
import 'misskey_api_provider.dart';
import 'shared_preferences_provider.dart';

/// 「最後に確認した時刻（lastSeen）以降の未読件数」を数えるバッジの共通実装。
///
/// 通知・DM・お知らせのバッジが同じ骨格（lastSeen の保存と読み出し、API から
/// 数え直し、ストリームで加算、クリア）を個別に書いており、完成度がばらついて
/// いた。lastSeen のパースは通知だけで3回インライン展開され、再接続時の取り直し
/// があるのは通知とDMだけ、といった具合だった。
///
/// 派生クラスは [prefsKeyPrefix] / [fetchItems] / [createdAtOf] / [isUnread] を
/// 実装する。リアルタイム受信が要るものは [streamOf]、クリア時にサーバーの
/// 既読化が要るものは [onClear] を上書きする。
///
/// サーバーの既読状態を書き換えずローカルの lastSeen で管理するのが基本方針。
/// 未読判定は「[isUnread] が真」かつ「lastSeen より後」の両方を満たすもの。
abstract class LastSeenBadgeNotifier<T> extends StateNotifier<int> {
  final Ref ref;
  final String accountId;
  StreamSubscription<T>? _streamSub;

  LastSeenBadgeNotifier(this.ref, this.accountId) : super(0) {
    _init();

    // ストリーミングサービスが差し替わったら購読し直す（アカウント切り替えなど）。
    ref.listen<StreamingService?>(streamingServiceProvider, (_, _) {
      _streamSub?.cancel();
      _streamSub = null;
      _subscribe();
    });

    // 自動再接続の成功時、切断中に取りこぼした分を API から補う。
    ref.listen<AsyncValue<StreamingStatus>>(streamingStatusProvider, (
      prev,
      next,
    ) {
      if (prev?.valueOrNull == StreamingStatus.reconnecting &&
          next.valueOrNull == StreamingStatus.connected) {
        refreshFromApi();
      }
    });

    // 生成時点で API が未確定なことがあるため、使えるようになったら数え直す。
    ref.listen<MisskeyApi?>(misskeyApiProvider, (_, next) {
      if (next != null) refreshFromApi();
    });
  }

  /// SharedPreferences のキー接頭辞。実際のキーは `<接頭辞>_<accountId>`。
  /// 既存の保存値を引き継ぐため、変更するとバッジが一度だけ増える点に注意。
  String get prefsKeyPrefix;

  /// バッジの母数を取得する。
  Future<List<T>> fetchItems(MisskeyApi api);

  /// [item] の発生時刻。lastSeen との比較に使う。
  DateTime createdAtOf(T item);

  /// lastSeen とは別に未読として数えてよいか。
  /// サーバー側の既読フラグや、自分自身の発言の除外をここで判定する。
  bool isUnread(T item);

  /// リアルタイム受信のストリーム。使わない場合は null（既定）。
  Stream<T>? streamOf(StreamingService streaming) => null;

  /// [clear] のときにサーバー側の既読化などを行う場合に上書きする。
  /// 例外は [clear] 側で握るため、ここで捕捉する必要はない。
  Future<void> onClear(MisskeyApi api) async {}

  String get _prefsKey => '${prefsKeyPrefix}_$accountId';

  /// 最後にバッジをクリアした時刻。未保存・壊れた値なら null。
  DateTime? get lastSeen {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  bool _countsAsUnread(T item, DateTime? seen) =>
      isUnread(item) && (seen == null || createdAtOf(item).isAfter(seen));

  Future<void> _init() async {
    await refreshFromApi();
    _subscribe();
  }

  void _subscribe() {
    final streaming = ref.read(streamingServiceProvider);
    if (streaming == null) return;
    _streamSub = streamOf(streaming)?.listen((item) {
      if (!mounted) return;
      if (_countsAsUnread(item, lastSeen)) state = state + 1;
    });
  }

  /// API から数え直す。WebSocket が切れているときのフォールバックでもある。
  /// 取得に失敗した場合は前回値を保つ（0 に落とすとバッジが消えてしまうため）。
  Future<void> refreshFromApi() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      final items = await fetchItems(api);
      if (!mounted) return;
      final seen = lastSeen;
      state = items.where((item) => _countsAsUnread(item, seen)).length;
    } catch (_) {
      // 取得失敗は無視する
    }
  }

  /// バッジを消す。lastSeen を現在時刻に更新し、以降の分だけを未読として数える。
  Future<void> clear() async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, DateTime.now().toIso8601String());

    final api = ref.read(misskeyApiProvider);
    if (api != null) {
      try {
        await onClear(api);
      } catch (_) {
        // サーバー側の既読化に失敗しても、ローカルの表示は消す
      }
    }

    if (mounted) state = 0;
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
