import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/call/infrastructure/adapters/openai_realtime_call_client.dart';

/// A small controllable fake that calls the provided callbacks so the
/// OpenAIRealtimeCallClient can be tested without networking.
class TestControlledRealtimeClient implements IRealtimeClient {
  TestControlledRealtimeClient({
    final void Function(String)? onText,
    final void Function(Uint8List)? onAudio,
    final void Function()? onCompleted,
    final void Function(Object)? onError,
    final void Function(String)? onUserTranscription,
  }) : _onText = onText,
       _onAudio = onAudio,
       _onCompleted = onCompleted,
       _onError = onError,
       _onUserTranscription = onUserTranscription;
  final void Function(String)? _onText;
  final void Function(Uint8List)? _onAudio;
  final void Function()? _onCompleted;
  final void Function(Object)? _onError;
  final void Function(String)? _onUserTranscription;

  bool connected = false;
  final List<List<int>> appended = [];
  final List<String> sentTexts = [];
  bool commitCalled = false;
  bool requestCalled = false;

  @override
  bool get isConnected => connected;

  @override
  void appendAudio(final List<int> bytes) {
    appended.add(List<int>.from(bytes));
  }

  @override
  Future<void> commitPendingAudio() async {
    commitCalled = true;
  }

  @override
  Future<void> connect({
    required final String systemPrompt,
    final String voice = '',
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  }) async {
    connected = true;
    // Optionally notify that session created would have occurred
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {
    requestCalled = true;
  }

  @override
  void sendText(final String text) {
    sentTexts.add(text);
  }

  @override
  void updateVoice(final String voice) {}

  @override
  Future<void> close() async {
    connected = false;
  }

  // Implementaciones de los nuevos métodos para tests
  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // Test implementation - could track calls if needed
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    // Test implementation - could track calls if needed
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // Test implementation - could track calls if needed
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // Test implementation - could track calls if needed
  }

  // Helpers to trigger callbacks
  void triggerText(final String t) => _onText?.call(t);
  void triggerAudio(final List<int> b) => _onAudio?.call(Uint8List.fromList(b));
  void triggerCompleted() => _onCompleted?.call();
  void triggerError(final Object e) => _onError?.call(e);
  void triggerUserTranscription(final String s) =>
      _onUserTranscription?.call(s);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    di.setTestRealtimeClientFactory(null);
  });

  test(
    'OpenAIRealtimeCallClient routes provider callbacks to streams and delegates calls',
    () async {
      TestControlledRealtimeClient? created;

      // Install test factory to return our controllable client
      di.setTestRealtimeClientFactory((
        final provider, {
        final model,
        final onText,
        final onAudio,
        final onCompleted,
        final onError,
        final onUserTranscription,
      }) {
        created = TestControlledRealtimeClient(
          onText: onText,
          onAudio: onAudio,
          onCompleted: onCompleted,
          onError: onError,
          onUserTranscription: onUserTranscription,
        );
        return created!;
      });

      final client = OpenAIRealtimeCallClient(model: 'test-model');

      await client.connect(systemPrompt: 'hello system', voice: 'marin');
      expect(client.isConnected, true);

      // Listen to streams
      final textEvents = <String>[];
      final audioEvents = <List<int>>[];
      final userTrans = <String>[];
      final completionEvents = <void>[];
      final errors = <Object>[];

      final subText = client.textStream.listen((final t) => textEvents.add(t));
      final subAudio = client.audioStream.listen(
        (final a) => audioEvents.add(a),
      );
      final subUser = client.userTranscriptionStream.listen(
        (final s) => userTrans.add(s),
      );
      final subComp = client.completionStream.listen(
        (_) => completionEvents.add(null),
      );
      final subErr = client.errorStream.listen((final e) => errors.add(e));

      // Trigger callbacks from the fake
      created!.triggerText('partial');
      created!.triggerUserTranscription('user spoken');
      created!.triggerAudio([1, 2, 3, 4]);
      created!.triggerCompleted();
      created!.triggerError(Exception('test error'));

      // Allow event loop
      await Future.delayed(const Duration(milliseconds: 50));

      expect(textEvents, contains('partial'));
      expect(userTrans, contains('user spoken'));
      expect(audioEvents.length, 1);
      expect(audioEvents.first, [1, 2, 3, 4]);
      expect(completionEvents.length, 1);
      expect(errors.isNotEmpty, true);

      // Test delegation: sendAudio should forward to underlying client
      client.sendAudio([10, 11, 12]);
      expect(created!.appended.length, 1);
      expect(created!.appended.first, [10, 11, 12]);

      // sendText delegates
      client.sendText('hola');
      expect(created!.sentTexts, contains('hola'));

      // requestResponse delegates
      client.requestResponse();
      expect(created!.requestCalled, true);

      // commitPendingAudio should be called by the controller after auto-commit delay
      client.sendAudio(List<int>.filled(9000, 1)); // exceed 8192 threshold
      // wait longer than the scheduled commit debounce (100ms)
      await Future.delayed(const Duration(milliseconds: 250));
      expect(created!.commitCalled, true);

      await subText.cancel();
      await subAudio.cancel();
      await subUser.cancel();
      await subComp.cancel();
      await subErr.cancel();

      await client.disconnect();
      expect(client.isConnected, false);
    },
  );
}
