import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/voice/infrastructure/adapters/voice_call_controller.dart';
import 'fakes/fake_voice_services.dart';
import 'test_setup.dart';

void main() {
  group('DSP regression safety', () {
    test('key DSP params remain stable', () async {
      // Initialize test environment with mocked audio playback
      await initializeTestEnvironment();

      final fakeAi = FakeCallsAiService();
      final c = VoiceCallController(aiService: fakeAi);

      // Expected golden values (update these only after conscious DSP change)
      expect(c.hpCutoffHzForTest, 80.0);
      expect(c.agcMaxGainForTest, 1.6);
      expect(c.agcAttackForTest, 0.25);
      expect(c.agcReleaseForTest, 0.08);
      expect(c.sendHoldMsForTest, 900);
      expect(c.earlyUnmuteProgressForTest, 0.60);
    });
  });
}
