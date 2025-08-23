import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/voice/infrastructure/transport/realtime_transport.dart';

/// Fake transport used to test adapter logic without network.
class FakeTransport implements RealtimeTransport {
  bool _connected = false;
  final List<Map<String, dynamic>> sentEvents = [];
  final List<Uint8List> appended = [];

  @override
  bool get isConnected => _connected;

  @override
  void Function(Object message)? onMessage;

  @override
  void Function(Object error)? onError;

  @override
  void Function()? onDone;

  @override
  Future<void> connect({required Map<String, dynamic> options}) async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  void sendEvent(Map<String, dynamic> event) {
    if (!_connected) return;
    sentEvents.add(Map<String, dynamic>.from(event));
  }

  @override
  void appendAudio(Uint8List bytes) {
    if (!_connected) return;
    appended.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> commitAudio() async {}
}

/// A small test adapter that mirrors the public behavior of OpenAITransportAdapter
/// but accepts an injected transport (composition) so tests can control messages.
class TestAdapter implements IRealtimeClient {
  final RealtimeTransport transport;
  final void Function(String)? onText;
  final void Function(Uint8List)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object)? onError;
  final void Function(String)? onUserTranscription;

  TestAdapter({
    required this.transport,
    this.onText,
    this.onAudio,
    this.onCompleted,
    this.onError,
    this.onUserTranscription,
  }) {
    transport.onMessage = _handleMessage;
    transport.onError = (e) => onError?.call(e);
    transport.onDone = () => onCompleted?.call();
  }

  void _handleMessage(Object msg) {
    try {
      if (msg is Map) {
        final type = (msg['type'] ?? '').toString();
        if (type.startsWith('response.audio_transcript.') && msg['delta'] is String) {
          final tx = (msg['delta'] as String).trim();
          if (tx.isNotEmpty) onText?.call(tx);
        }
        if (msg['delta'] is Map && msg['delta']['audio'] is String) {
          final base64Audio = msg['delta']['audio'] as String;
          try {
            final bytes = base64Decode(base64Audio);
            onAudio?.call(Uint8List.fromList(bytes));
          } catch (e) {
            onError?.call(e);
          }
        }
      } else if (msg is List<int>) {
        onAudio?.call(Uint8List.fromList(msg));
      }
    } catch (e) {
      onError?.call(e);
    }
  }

  @override
  Future<void> connect({
    required String systemPrompt,
    String voice = 'sage',
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    await transport.connect(options: options ?? {});
    transport.sendEvent({
      'type': 'session.update',
      'session': {
        'instructions': systemPrompt,
        'modalities': ['audio', 'text'],
        'voice': voice,
      },
    });
  }

  @override
  void updateVoice(String voice) => transport.sendEvent({
    'type': 'session.update',
    'session': {'voice': voice},
  });

  @override
  void appendAudio(List<int> bytes) => transport.appendAudio(Uint8List.fromList(bytes));

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    final modalities = <String>[];
    if (audio) modalities.add('audio');
    if (text) modalities.add('text');
    transport.sendEvent({
      'type': 'response.create',
      'response': {'modalities': modalities},
    });
  }

  @override
  Future<void> commitPendingAudio() async => transport.commitAudio();

  @override
  void sendText(String text) => transport.sendEvent({
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
  Future<void> close() async => await transport.disconnect();

  @override
  bool get isConnected => transport.isConnected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TestAdapter sends correct events to transport on connect/sendText/requestResponse/append', () async {
    final fake = FakeTransport();
    final adapter = TestAdapter(transport: fake);

    expect(adapter.isConnected, false);
    await adapter.connect(systemPrompt: 'sys', voice: 'v');
    expect(adapter.isConnected, true);

    // session.update sent
    expect(fake.sentEvents.any((e) => e['type'] == 'session.update'), true);

    adapter.sendText('hola');
    expect(fake.sentEvents.any((e) => e['type'] == 'conversation.item.create'), true);

    adapter.requestResponse(audio: true, text: false);
    expect(fake.sentEvents.any((e) => e['type'] == 'response.create'), true);

    adapter.appendAudio([1, 2, 3]);
    expect(fake.appended.length, 1);
    expect(fake.appended.first, [1, 2, 3]);

    await adapter.close();
    expect(adapter.isConnected, false);
  });

  test('TestAdapter processes incoming JSON and binary messages and triggers callbacks', () async {
    final fake = FakeTransport();
    final texts = <String>[];
    final audios = <List<int>>[];
    final completions = <void>[];
    final errors = <Object>[];

    final adapter = TestAdapter(
      transport: fake,
      onText: (t) => texts.add(t),
      onAudio: (b) => audios.add(b),
      onCompleted: () => completions.add(null),
      onError: (e) => errors.add(e),
    );

    await adapter.connect(systemPrompt: 'x', voice: 'v');

    // Simulate incoming text delta
    fake.onMessage?.call({'type': 'response.audio_transcript.partial', 'delta': 'hola parcial'});
    // base64 chunk
    final b64 = base64Encode([1, 2, 3, 4]);
    fake.onMessage?.call({
      'type': 'response.audio.delta',
      'delta': {'audio': b64},
    });
    // raw binary frame
    fake.onMessage?.call([9, 8, 7]);
    // done
    fake.onDone?.call();

    await Future.delayed(const Duration(milliseconds: 20));

    expect(texts, contains('hola parcial'));
    expect(audios.length, greaterThanOrEqualTo(2));
    expect(audios.any((l) => l[0] == 1 && l[1] == 2), true);
    expect(audios.any((l) => l[0] == 9 && l[1] == 8), true);
    expect(completions.length, 1);
    expect(errors.isEmpty, true);

    await adapter.close();
  });
}
