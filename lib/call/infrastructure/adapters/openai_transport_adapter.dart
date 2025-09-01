import 'dart:typed_data';
import 'dart:convert';

import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import '../transport/openai_transport.dart';

/// Adapter that implements IRealtimeClient using a RealtimeTransport.
class OpenAITransportAdapter implements IRealtimeClient {
  final OpenAITransport _transport;
  final void Function(String)? onText;
  final void Function(Uint8List)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object)? onError;
  final void Function(String)? onUserTranscription;

  OpenAITransportAdapter({
    String? model,
    this.onText,
    this.onAudio,
    this.onCompleted,
    this.onError,
    this.onUserTranscription,
  }) : _transport = OpenAITransport(model: model) {
    _transport.onMessage = _handleMessage;
    _transport.onError = (e) => onError?.call(e);
    _transport.onDone = () => onCompleted?.call();
  }

  void _handleMessage(Object msg) {
    // Naive routing: real implementation should parse event shapes precisely
    try {
      if (msg is Map) {
        final type = (msg['type'] ?? '').toString();
        if (type.startsWith('response.audio_transcript.') &&
            msg['delta'] is String) {
          final tx = (msg['delta'] as String).trim();
          if (tx.isNotEmpty) onText?.call(tx);
        }
        // Extract audio fields if present (OpenAI may send audio as base64 inside delta.audio)
        if (msg['delta'] is Map && (msg['delta']['audio'] is String)) {
          final base64Audio = msg['delta']['audio'] as String;
          try {
            final bytes = base64Decode(base64Audio);
            onAudio?.call(bytes);
          } catch (e) {
            // If decoding fails, forward error
            onError?.call(e);
          }
        }
      } else if (msg is List<int>) {
        // Binary audio frame received directly
        onAudio?.call(Uint8List.fromList(msg));
      }
    } catch (e) {
      onError?.call(e);
    }
  }

  @override
  Future<void> connect({
    required String systemPrompt,
    String? voice,
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    await _transport.connect(options: options ?? {});
    // After connection, send session.update with initial settings
    _transport.sendEvent({
      'type': 'session.update',
      'session': {
        'instructions': systemPrompt,
        'modalities': ['audio', 'text'],
        'voice': voice ?? 'sage',
      },
    });
  }

  @override
  void updateVoice(String voice) => _transport.sendEvent({
    'type': 'session.update',
    'session': {'voice': voice},
  });

  @override
  void appendAudio(List<int> bytes) =>
      _transport.appendAudio(Uint8List.fromList(bytes));

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    final modalities = <String>[];
    if (audio) modalities.add('audio');
    if (text) modalities.add('text');
    _transport.sendEvent({
      'type': 'response.create',
      'response': {'modalities': modalities},
    });
  }

  @override
  Future<void> commitPendingAudio() async => _transport.commitAudio();

  @override
  void sendText(String text) => _transport.sendEvent({
    'type': 'conversation.item.create',
    'item': {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': text},
      ],
    },
  });

  @override
  Future<void> close() async => await _transport.disconnect();

  @override
  bool get isConnected => _transport.isConnected;
}
