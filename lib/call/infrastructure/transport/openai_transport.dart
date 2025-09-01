import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_chan/core/network_connectors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/call/domain/interfaces/realtime_transport_service.dart';

/// Skeleton OpenAI transport: handles WebSocket connection and forwards raw
/// messages to the adapter via onMessage/onError/onDone callbacks.
class OpenAITransport implements RealtimeTransportService {
  final String model;
  WsChannel? _channel;
  bool _connected = false;

  /// Public read-only connection state for transports.
  @override
  bool get isConnected => _connected;

  OpenAITransport({String? model})
    : model = model ?? Config.requireOpenAIRealtimeModel();

  @override
  Future<void> connect({required Map<String, dynamic> options}) async {
    final apiKey = Config.getOpenAIKey();
    if (apiKey.trim().isEmpty) throw Exception('Missing OpenAI API key');
    final uri = Uri.parse('wss://api.openai.com/v1/realtime?model=$model');
    // Use injectable connector so tests can override and avoid real network
    _channel = WebSocketConnector.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'OpenAI-Beta': 'realtime=v1',
      },
    );
    _connected = true;
    _channel!.stream.listen(
      (msg) {
        try {
          // Try to decode JSON messages; binary frames will be List<int>
          if (msg is String) {
            final decoded = jsonDecode(msg);
            onMessage?.call(decoded);
          } else {
            onMessage?.call(msg);
          }
        } catch (e) {
          onError?.call(e);
        }
      },
      onError: (e) {
        onError?.call(e);
        _connected = false;
      },
      onDone: () {
        onDone?.call();
        _connected = false;
      },
    );
  }

  @override
  Future<void> disconnect() async {
    if (_connected) {
      try {
        await _channel?.sink.close();
      } catch (_) {}
    }
    _connected = false;
  }

  @override
  void sendEvent(Map<String, dynamic> event) {
    if (!_connected) return;
    try {
      _channel?.sink.add(jsonEncode(event));
    } catch (e) {
      onError?.call(e);
    }
  }

  @override
  void appendAudio(Uint8List bytes) {
    if (!_connected) return;
    try {
      // OpenAI accepts base64 in JSON events; adapters may choose to send
      // via sendEvent with input_audio_buffer.append or via binary frames.
      sendEvent({
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(bytes),
      });
    } catch (e) {
      onError?.call(e);
    }
  }

  @override
  @override
  Future<void> commitAudio() async {
    if (!_connected) return;
    sendEvent({'type': 'input_audio_buffer.commit'});
  }

  @override
  void Function(Object message)? onMessage;

  @override
  void Function(Object error)? onError;

  @override
  void Function()? onDone;
}
