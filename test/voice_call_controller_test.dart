import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/voice/infrastructure/adapters/voice_call_controller.dart';
import 'fakes/fake_realtime_impl.dart';
import 'fakes/fake_voice_services.dart';
import 'fakes/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('VoiceCallController basic integration with IRealtimeClient', () {
    late VoiceCallController controller;
    late FakeRealtimeIClient fakeClient;

    setUp(() async {
      // Use a minimal fake AI service since VoiceCallController requires an aiService in ctor
      final fakeAi = FakeCallsAiService();
      controller = VoiceCallController(
        aiService: fakeAi,
        audioPlayer: FakeAudioPlayer(),
        ringPlayer: FakeAudioPlayer(),
      );
      fakeClient = FakeRealtimeIClient();
      // inject fake client directly
      controller.setTestClientForTests(fakeClient);
      // avoid initializing real platform audio in tests
      controller.setTestMicStartedForTests(true);
    });

    test('sendAudio forwards to client.appendAudio when not muted', () async {
      // Ensure controller thinks it's connected and not muted
      controller.setTestConnectedForTests(true);
      controller.setMuted(false);

      final chunk = Uint8List.fromList(List<int>.filled(160, 0));
      controller.sendAudio(chunk);

      expect(fakeClient.appended.length, 1);
      expect(fakeClient.appended.first.length, chunk.length);
    });

    test('VAD onSpeechEnd triggers commitPendingAudio', () async {
      controller.setTestConnectedForTests(true);
      // Simulate VAD callback calling commit
      await controller.testInvokeVadOnSpeechEnd();
      expect(fakeClient.commitCalled, true);
    });

    test('salvageStartCall sends accept message via sendText', () async {
      controller.setTestConnectedForTests(true);
      await controller.testCallSalvageStartCall();
      // After salvage, FakeRealtimeClient should have received a sendText
      expect(fakeClient.sentTexts.isNotEmpty, true);
    });
  });
}
