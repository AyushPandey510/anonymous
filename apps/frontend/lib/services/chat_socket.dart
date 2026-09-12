import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

sealed class WsEvent {
  const WsEvent();
}

class WsMessageEvent extends WsEvent {
  const WsMessageEvent(this.message);

  final MessageData message;
}

class WsPollUpdatedEvent extends WsEvent {
  const WsPollUpdatedEvent();
}

class WsReactionEvent extends WsEvent {
  const WsReactionEvent({
    required this.messageId,
    required this.emoji,
    required this.count,
  });

  final String messageId;
  final String emoji;
  final int count;
}

class ChatSocket {
  ChatSocket({
    required this.baseUrl,
    required this.getAccessToken,
    required this.spaceId,
  });

  final String baseUrl;
  final String Function() getAccessToken;
  final String spaceId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _retries = 0;

  final _controller = StreamController<WsEvent>.broadcast();

  Stream<WsEvent> get events => _controller.stream;

  String get _url {
    final base = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return '$base/ws/spaces/$spaceId';
  }

  void connect() {
    if (_disposed) return;
    final token = getAccessToken();
    if (token.isEmpty) {
      _scheduleReconnect();
      return;
    }
    _channel = IOWebSocketChannel.connect(
      Uri.parse(_url),
      headers: {'Authorization': 'Bearer $token'},
    );
    _subscription = _channel!.stream.listen(
      _onData,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _onData(dynamic data) {
    final event = decode(data);
    if (event != null) _controller.add(event);
  }

  static WsEvent? decode(dynamic data) {
    try {
      final json = jsonDecode(data as String);
      if (json is! Map<String, dynamic>) return null;
      switch (json['type']) {
        case 'poll_updated':
          return const WsPollUpdatedEvent();
        case 'message':
          final message = json['message'];
          if (message is! Map<String, dynamic>) return null;
          return WsMessageEvent(MessageData.fromJson(message));
        case 'reaction':
          return WsReactionEvent(
            messageId: json['message_id'] as String,
            emoji: json['emoji'] as String,
            count: json['count'] as int,
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _subscription?.cancel();
    _subscription = null;
    final delay = Duration(milliseconds: 500 * (1 << _retries.clamp(0, 4)));
    _retries++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _controller.close();
  }
}
