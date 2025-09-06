import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import '../test_setup.dart';
import '../fakes/fake_voice_services.dart';
import '../fakes/fake_audio_player.dart';

/// A minimal fake realtime client that emulates the buffered (Gemini/Google)
/// orchestrator behavior used by the CallController in buffered mode.
class _FakeBufferedClient implements IRealtimeClient {
  _FakeBufferedClient({final void Function(String)? onUserTranscription}) {
    _onUserTranscription = onUserTranscription;
  }
  bool connected = false;
  bool commitCalled = false;
  void Function(String)? _onUserTranscription;

  @override
  bool get isConnected => connected;

  @override
  void appendAudio(final List<int> bytes) {
    // buffered flow doesn't use appendAudio in tests
  }

  @override
  Future<void> commitPendingAudio() async {
    commitCalled = true;
    // Simulate that the provider transcribed the just-committed audio and
    // invokes the onUserTranscription callback with the test string.
    await Future.delayed(const Duration(milliseconds: 20));
    _onUserTranscription?.call('transcripcion de prueba');
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
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {}

  @override
  void sendText(final String text) {}

  @override
  void updateVoice(final String voice) {}

  @override
  Future<void> close() async {
    connected = false;
  }

  // Implementaciones por defecto de los nuevos métodos
  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // Fake implementation for test
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    // Fake implementation for test
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // Fake implementation for test
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // Fake implementation for test
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Buffered flow integration test', () {
    setUp(() async {
      await initializeTestEnvironment();
    });

    test('VAD commit triggers STT and user transcription callback', () async {
      // Install a DI factory that returns our fake buffered client wired to
      // the callbacks CallController expects
      di.setTestRealtimeClientFactory((
        final provider, {
        final model,
        final onText,
        final onAudio,
        final onCompleted,
        final onError,
        final onUserTranscription,
      }) {
        return _FakeBufferedClient(onUserTranscription: onUserTranscription);
      });

      final fakeAi = FakeCallsAiService();
      final fakePlayer = FakeAudioPlayer();
      final controller = CallController(
        aiService: fakeAi,
        audioPlayer: fakePlayer,
        ringPlayer: fakePlayer,
      );
      // Avoid real platform audio initialization in tests
      controller.setTestMicStartedForTests(true);

      String? receivedUserTranscription;
      // Start a continuous call using provider override 'google' to force buffered flow
      await controller.startContinuousCall(
        systemPrompt: 'test',
        providerNameOverride: 'google',
        onText: (final t) {},
        onUserTranscription: (final t) {
          receivedUserTranscription = t;
        },
      );

      // Ensure the controller believes it's connected (connect() in fake sets it)
      controller.setTestConnectedForTests(true);

      // Simulate VAD end of speech which should call commitPendingAudio() on the client
      await controller.testInvokeVadOnSpeechEnd();

      // Allow a short time for the fake client to call back
      await Future.delayed(const Duration(milliseconds: 100));

      expect(receivedUserTranscription, isNotNull);
      expect(receivedUserTranscription, contains('transcripcion'));
    });
  });
}
