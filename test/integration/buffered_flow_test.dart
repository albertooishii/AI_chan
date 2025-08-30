import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/voice/infrastructure/adapters/voice_call_controller.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import '../test_setup.dart';
import '../fakes/fake_voice_services.dart';
import '../fakes/fake_audio_player.dart';

/// A minimal fake realtime client that emulates the buffered (Gemini/Google)
/// orchestrator behavior used by the VoiceCallController in buffered mode.
class _FakeBufferedClient implements IRealtimeClient {
  bool connected = false;
  bool commitCalled = false;
  void Function(String)? _onUserTranscription;

  _FakeBufferedClient({void Function(String)? onUserTranscription}) {
    _onUserTranscription = onUserTranscription;
  }

  @override
  bool get isConnected => connected;

  @override
  void appendAudio(List<int> bytes) {
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
    required String systemPrompt,
    String voice = '',
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    connected = true;
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {}

  @override
  void sendText(String text) {}

  @override
  void updateVoice(String voice) {}

  @override
  Future<void> close() async {
    connected = false;
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
      // the callbacks VoiceCallController expects
      di.setTestRealtimeClientFactory((
        provider, {
        model,
        onText,
        onAudio,
        onCompleted,
        onError,
        onUserTranscription,
      }) {
        return _FakeBufferedClient(onUserTranscription: onUserTranscription);
      });

      final fakeAi = FakeCallsAiService();
      final fakePlayer = FakeAudioPlayer();
      final controller = VoiceCallController(
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
        onText: (t) {},
        onUserTranscription: (t) {
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
