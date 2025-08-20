import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import '../fakes/fake_ai_service.dart';

void main() {
  test(
    'generateAIBiographyWithAI returns AiChanProfile given fake AIService',
    () async {
      // Inject the shared fake
      AIService.testOverride = FakeAIService.forBiography();

      final profile = await generateAIBiographyWithAI(
        userName: 'UserTest',
        aiName: 'AiTest',
        userBirthday: DateTime(1995, 6, 15),
        meetStory: 'Una historia de prueba',
        userCountryCode: 'ES',
        aiCountryCode: 'JP',
        seed: 42,
      );

      expect(profile, isA<AiChanProfile>());
      expect(profile.biography, contains('datos_personales'));

      // Clear override
      AIService.testOverride = null;
    },
  );
}
