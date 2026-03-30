import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../data/models/note_model.dart';
import '../../shared/providers/account_provider.dart';
import '../../shared/providers/settings_provider.dart';

// タイムラインタイプ → Misskeyチャンネル名のマッピング
const _channelMap = {
  'home': 'homeTimeline',
  'local': 'localTimeline',
  'social': 'hybridTimeline',
  'global': 'globalTimeline',
};

class StreamingService {
  WebSocketChannel? _channel;
  final _controllers = <String, StreamController<NoteModel>>{};
  final _subscriptions = <String, String>{}; // channelId -> timelineType
  bool _connected = false;
  final String host;
  final String token;

  StreamingService({required this.host, required this.token});

  Future<void> connect() async {
    if (_connected) return;

    final uri = Uri.parse('wss://$host/streaming?i=$token');
    _channel = WebSocketChannel.connect(uri);
    _connected = true;

    _channel!.stream.listen(
      _onMessage,
      onError: (_) => _handleDisconnect(),
      onDone: _handleDisconnect,
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      if (data['type'] != 'channel') return;

      final body = data['body'] as Map<String, dynamic>?;
      if (body == null) return;

      final id = body['id'] as String?;
      if (id == null) return;

      final timelineType = _subscriptions[id];
      if (timelineType == null) return;

      final type = body['type'] as String?;
      if (type != 'note') return;

      final noteData = body['body'] as Map<String, dynamic>?;
      if (noteData == null) return;

      final note = NoteModel.fromJson(noteData, host: host);
      _controllers[timelineType]?.add(note);
    } catch (_) {
      // パースエラーは無視
    }
  }

  Stream<NoteModel>? subscribeTimeline(String timelineType) {
    final channelName = _channelMap[timelineType];
    if (channelName == null) return null;

    _controllers.putIfAbsent(
      timelineType,
      () => StreamController<NoteModel>.broadcast(),
    );

    final id = const Uuid().v4();
    _subscriptions[id] = timelineType;

    _channel?.sink.add(
      jsonEncode({
        'type': 'connect',
        'body': {'channel': channelName, 'id': id},
      }),
    );

    return _controllers[timelineType]!.stream;
  }

  void _handleDisconnect() {
    _connected = false;
    // 再接続は利用側で行う
  }

  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
    _controllers.clear();
    _subscriptions.clear();
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
