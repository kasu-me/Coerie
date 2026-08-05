import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/note_model.dart';
import '../../data/models/notification_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/settings_provider.dart';

// タイムラインタイプ → Misskeyチャンネル名のマッピング
const _channelMap = {
  'home': 'homeTimeline',
  'local': 'localTimeline',
  'social': 'hybridTimeline',
  'global': 'globalTimeline',
};

enum StreamingStatus { connected, reconnecting, serverDown }

/// subNote で受け取るノート更新イベント
class NoteUpdateEvent {
  final String noteId;
  final String type; // 'reacted' | 'unreacted' | 'pollVoted' | 'deleted'
  final String? reaction;
  final String? userId;

  const NoteUpdateEvent({
    required this.noteId,
    required this.type,
    this.reaction,
    this.userId,
  });
}

class StreamingService {
  WebSocketChannel? _channel;
  final _timelineControllers = <String, StreamController<NoteModel>>{};

  /// channelId -> timelineType（再接続時にクリアして再登録）
  final _channelSubscriptions = <String, String>{};

  /// timelineType -> 現在発行中の channelId（disconnect と再登録に使う）
  final _channelIdByTimeline = <String, String>{};

  /// timelineType -> 購読者数。
  /// 0 から 1 になったときだけ connect、0 に戻ったときだけ disconnect を送る。
  /// キーはそのまま「購読中のタイムライン」として再接続時の再登録にも使う。
  final _timelineSubCounts = <String, int>{};
  final _notificationController =
      StreamController<NotificationModel>.broadcast();
  final _noteUpdateController = StreamController<NoteUpdateEvent>.broadcast();
  final _chatMessageController = StreamController<ChatMessageModel>.broadcast();
  final _statusController = StreamController<StreamingStatus>.broadcast();
  // 再接続が完了したときに発火する（切断中に取りこぼした状態の再取得トリガー用）
  final _reconnectedController = StreamController<void>.broadcast();
  final _noteSubCounts = <String, int>{}; // noteId -> subscriber count
  bool _connected = false;
  bool _reconnecting = false;
  bool _disposed = false;
  String? _mainChannelId;
  final String host;
  final String token;

  StreamingService({required this.host, required this.token});

  /// 通知のリアルタイムストリーム
  Stream<NotificationModel> get notificationStream =>
      _notificationController.stream;

  /// ノート更新イベントのストリーム（subNote で購読したノートのみ配信）
  Stream<NoteUpdateEvent> get noteUpdateStream => _noteUpdateController.stream;

  /// チャット（DM）メッセージのリアルタイムストリーム（main チャンネル経由）
  Stream<ChatMessageModel> get chatMessageStream =>
      _chatMessageController.stream;

  /// 接続状態ストリーム
  Stream<StreamingStatus> get statusStream => _statusController.stream;

  /// 再接続が完了したときに発火するストリーム。
  /// 切断中に取りこぼしたリアクション等を再取得するためのトリガーに使う。
  Stream<void> get reconnectedStream => _reconnectedController.stream;

  /// 初回接続（失敗しても静かに終了）
  Future<void> connect() async {
    if (_connected || _disposed) return;
    await _doConnect();
  }

  /// 実際の接続処理。成功したら true を返す。
  Future<bool> _doConnect() async {
    try {
      final uri = Uri.parse('wss://$host/streaming?i=$token');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 10));

      if (_disposed) {
        channel.sink.close();
        return false;
      }

      _channel = channel;
      _connected = true;

      _channel!.stream.listen(
        _onMessage,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );

      _connectMainChannel();
      _resubscribeAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _connectMainChannel() {
    _mainChannelId = const Uuid().v4();
    _channel?.sink.add(
      jsonEncode({
        'type': 'connect',
        'body': {'channel': 'main', 'id': _mainChannelId},
      }),
    );
  }

  /// サーバーへ connect 済みのタイムラインチャンネル数。
  /// 同じタイムラインを重複して登録していないかの回帰検知にのみ使う。
  @visibleForTesting
  int get debugChannelCount => _channelIdByTimeline.length;

  /// [timelineType] が購読可能か（対応する Misskey チャンネルがあるか）。
  static bool _isKnownTimeline(String timelineType) =>
      timelineType.startsWith('channel:') ||
      _channelMap.containsKey(timelineType);

  /// [timelineType] に対応するチャンネルへ connect を送り、
  /// 発行した channelId を控える。未対応の型なら何もしない。
  void _openChannel(String timelineType) {
    final isChannelTimeline = timelineType.startsWith('channel:');
    final channelName = isChannelTimeline
        ? 'channel'
        : _channelMap[timelineType];
    if (channelName == null) return;

    final id = const Uuid().v4();
    _channelSubscriptions[id] = timelineType;
    _channelIdByTimeline[timelineType] = id;

    final body = <String, dynamic>{'channel': channelName, 'id': id};
    if (isChannelTimeline) {
      body['params'] = {'channelId': timelineType.substring(8)};
    }
    _channel?.sink.add(jsonEncode({'type': 'connect', 'body': body}));
  }

  /// 再接続後、既存の購読をすべて再登録する
  void _resubscribeAll() {
    // タイムラインチャンネル
    for (final timelineType in _timelineSubCounts.keys) {
      _openChannel(timelineType);
    }
    // subNote
    for (final noteId in _noteSubCounts.keys) {
      _channel?.sink.add(
        jsonEncode({
          'type': 'subNote',
          'body': {'id': noteId},
        }),
      );
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'channel') {
        _handleChannelMessage(data['body'] as Map<String, dynamic>?);
      } else if (type == 'noteUpdated') {
        _handleNoteUpdated(data['body'] as Map<String, dynamic>?);
      }
    } catch (_) {
      // パースエラーは無視
    }
  }

  void _handleChannelMessage(Map<String, dynamic>? body) {
    if (body == null) return;

    final id = body['id'] as String?;
    if (id == null) return;

    final eventType = body['type'] as String?;
    final eventBody = body['body'] as Map<String, dynamic>?;
    if (eventBody == null) return;

    // main チャンネルのイベント
    if (id == _mainChannelId) {
      if (eventType == 'notification') {
        final notification = NotificationModel.fromJson(eventBody, host: host);
        _notificationController.add(notification);
      } else if (eventType == 'newChatMessage') {
        _chatMessageController.add(ChatMessageModel.fromJson(eventBody));
      }
      return;
    }

    // タイムライン チャンネルのイベント
    final timelineType = _channelSubscriptions[id];
    if (timelineType == null) return;

    if (eventType == 'note') {
      final note = NoteModel.fromJson(eventBody, host: host);
      _timelineControllers[timelineType]?.add(note);
    }
  }

  void _handleNoteUpdated(Map<String, dynamic>? body) {
    if (body == null) return;
    final noteId = body['id'] as String?;
    if (noteId == null) return;

    // 購読していないノートは無視
    if (!_noteSubCounts.containsKey(noteId)) return;

    final type = body['type'] as String?;
    if (type == null) return;

    final eventBody = body['body'] as Map<String, dynamic>?;
    _noteUpdateController.add(
      NoteUpdateEvent(
        noteId: noteId,
        type: type,
        reaction: eventBody?['reaction'] as String?,
        userId: eventBody?['userId'] as String?,
      ),
    );
  }

  void _handleDisconnect() {
    // 破棄済み・すでに再接続中は何もしない
    if (_disposed || _reconnecting) return;
    _connected = false;
    _reconnecting = true;
    _channel = null;
    // 旧チャンネルIDはすべて無効になるのでクリア
    // （_timelineSubCounts は再登録に使うので保持する）
    _channelSubscriptions.clear();
    _channelIdByTimeline.clear();

    if (!_statusController.isClosed) {
      _statusController.add(StreamingStatus.reconnecting);
    }

    // 2秒後に再接続シーケンスを開始する（_tryReconnect 内でバックオフ再試行する）
    Future.delayed(const Duration(seconds: 2), _tryReconnect);
  }

  Future<void> _tryReconnect() async {
    // 初回以降の再試行待機時間（秒）
    const retryDelays = [5, 10, 20, 30, 60];

    for (int i = 0; i <= retryDelays.length; i++) {
      if (_disposed) return;
      final success = await _doConnect();
      if (success) {
        _reconnecting = false;
        if (!_statusController.isClosed) {
          _statusController.add(StreamingStatus.connected);
        }
        // 切断中に取りこぼした状態を再取得させるため再接続イベントを通知する
        if (!_reconnectedController.isClosed) {
          _reconnectedController.add(null);
        }
        return;
      }
      // まだ試行回数が残っている場合はバックオフして再試行
      if (i < retryDelays.length) {
        await Future.delayed(Duration(seconds: retryDelays[i]));
      }
    }

    // 全試行失敗
    _reconnecting = false;
    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(StreamingStatus.serverDown);
    }
  }

  /// 手動で再接続を試みる（バナーの「再接続」ボタン用）
  void retryConnect() {
    if (_disposed || _reconnecting) return;
    _connected = false;
    _reconnecting = true;
    _channel?.sink.close();
    _channel = null;
    _channelSubscriptions.clear();
    _channelIdByTimeline.clear();
    if (!_statusController.isClosed) {
      _statusController.add(StreamingStatus.reconnecting);
    }
    _tryReconnect();
  }

  /// [timelineType] のリアルタイム配信を購読する。未対応の型なら null。
  ///
  /// 同じ型から複数回呼ばれても connect は1回しか送らない。以前は呼ばれるたびに
  /// 新しい channelId で connect しており、タブの切り替えや再購読のたびに
  /// サーバー側のチャンネルが積み上がっていた。その結果、同じノートが購読数だけ
  /// 重複配信され、新着バッジが多重にカウントされていた。
  ///
  /// 購読をやめるときは必ず [unsubscribeTimeline] を呼ぶこと。
  Stream<NoteModel>? subscribeTimeline(String timelineType) {
    if (!_isKnownTimeline(timelineType)) return null;

    final controller = _timelineControllers.putIfAbsent(
      timelineType,
      () => StreamController<NoteModel>.broadcast(),
    );

    final count = _timelineSubCounts[timelineType] ?? 0;
    _timelineSubCounts[timelineType] = count + 1;
    if (count == 0) _openChannel(timelineType);

    return controller.stream;
  }

  /// [subscribeTimeline] の購読を解除する。
  /// 参照カウントが 0 になった時点でサーバーへ disconnect を送る。
  void unsubscribeTimeline(String timelineType) {
    final count = _timelineSubCounts[timelineType] ?? 0;
    if (count == 0) return;
    if (count > 1) {
      _timelineSubCounts[timelineType] = count - 1;
      return;
    }

    _timelineSubCounts.remove(timelineType);
    final id = _channelIdByTimeline.remove(timelineType);
    if (id != null) {
      _channelSubscriptions.remove(id);
      _channel?.sink.add(
        jsonEncode({
          'type': 'disconnect',
          'body': {'id': id},
        }),
      );
    }
    // 購読者がいなくなったので、配信先のコントローラも畳む。
    _timelineControllers.remove(timelineType)?.close();
  }

  /// 指定ノートへのリアルタイム更新を購読する。
  /// 複数箇所から呼ばれても重複送信しないよう参照カウントで管理。
  void subNote(String noteId) {
    final count = _noteSubCounts[noteId] ?? 0;
    _noteSubCounts[noteId] = count + 1;
    if (count == 0) {
      _channel?.sink.add(
        jsonEncode({
          'type': 'subNote',
          'body': {'id': noteId},
        }),
      );
    }
  }

  /// subNote の購読を解除する。
  void unsubNote(String noteId) {
    final count = _noteSubCounts[noteId] ?? 0;
    if (count <= 1) {
      _noteSubCounts.remove(noteId);
      _channel?.sink.add(
        jsonEncode({
          'type': 'unsubNote',
          'body': {'id': noteId},
        }),
      );
    } else {
      _noteSubCounts[noteId] = count - 1;
    }
  }

  void dispose() {
    _disposed = true;
    for (final ctrl in _timelineControllers.values) {
      ctrl.close();
    }
    _timelineControllers.clear();
    _channelSubscriptions.clear();
    _channelIdByTimeline.clear();
    _timelineSubCounts.clear();
    _noteSubCounts.clear();
    _notificationController.close();
    _noteUpdateController.close();
    _chatMessageController.close();
    _statusController.close();
    _reconnectedController.close();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}

// Riverpodプロバイダー
final streamingServiceProvider = Provider<StreamingService?>((ref) {
  final account = ref.watch(activeAccountProvider);
  // 設定全体を watch すると、フォントサイズ等の無関係な変更でも
  // このプロバイダーが再生成され、WebSocket の再接続と
  // subNote 購読の消失を招くため、必要な項目だけを購読する。
  final realtimeUpdate = ref.watch(
    settingsProvider.select((s) => s.realtimeUpdate),
  );

  if (account == null || !realtimeUpdate) return null;

  final service = StreamingService(host: account.host, token: account.token);
  service.connect();

  ref.onDispose(service.dispose);

  return service;
});

/// WebSocket の接続状態を購読するプロバイダー
final streamingStatusProvider = StreamProvider<StreamingStatus>((ref) {
  final service = ref.watch(streamingServiceProvider);
  if (service == null) return const Stream.empty();
  return service.statusStream;
});
