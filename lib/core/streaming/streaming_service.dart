import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

  /// どのタイムラインを購読していたかを記憶（再接続後に再登録用）
  final _subscribedTimelines = <String>{};
  final _notificationController =
      StreamController<NotificationModel>.broadcast();
  final _noteUpdateController = StreamController<NoteUpdateEvent>.broadcast();
  final _statusController = StreamController<StreamingStatus>.broadcast();
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

  /// 接続状態ストリーム
  Stream<StreamingStatus> get statusStream => _statusController.stream;

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

  /// 再接続後、既存の購読をすべて再登録する
  void _resubscribeAll() {
    // タイムラインチャンネル
    for (final timelineType in _subscribedTimelines) {
      final channelName = _channelMap[timelineType];
      if (channelName == null) continue;
      final id = const Uuid().v4();
      _channelSubscriptions[id] = timelineType;
      _channel?.sink.add(
        jsonEncode({
          'type': 'connect',
          'body': {'channel': channelName, 'id': id},
        }),
      );
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
    // 旧チャンネルIDはすべて無効になるのでクリア（_subscribedTimelines は保持）
    _channelSubscriptions.clear();

    if (!_statusController.isClosed) {
      _statusController.add(StreamingStatus.reconnecting);
    }

    // 2秒後に1回だけ再接続を試みる
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
    if (!_statusController.isClosed) {
      _statusController.add(StreamingStatus.reconnecting);
    }
    _tryReconnect();
  }

  Stream<NoteModel>? subscribeTimeline(String timelineType) {
    final channelName = _channelMap[timelineType];
    if (channelName == null) return null;

    // 再接続時に再登録できるよう記憶
    _subscribedTimelines.add(timelineType);

    _timelineControllers.putIfAbsent(
      timelineType,
      () => StreamController<NoteModel>.broadcast(),
    );

    final id = const Uuid().v4();
    _channelSubscriptions[id] = timelineType;

    _channel?.sink.add(
      jsonEncode({
        'type': 'connect',
        'body': {'channel': channelName, 'id': id},
      }),
    );

    return _timelineControllers[timelineType]!.stream;
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
    _subscribedTimelines.clear();
    _noteSubCounts.clear();
    _notificationController.close();
    _noteUpdateController.close();
    _statusController.close();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}

// Riverpodプロバイダー
final streamingServiceProvider = Provider<StreamingService?>((ref) {
  final account = ref.watch(activeAccountProvider);
  final settings = ref.watch(settingsProvider);

  if (account == null || !settings.realtimeUpdate) return null;

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
