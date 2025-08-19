import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/utils/onboarding_utils.dart';
import 'fakes/fake_appearance_generator.dart';
import 'fakes/fake_ai_service.dart';
import 'package:ai_chan/services/ai_service.dart';

void main() {
  test('generateFullBiographyFlexible integrates appearance generator', () async {
    // Inject fake AI service for downstream generators
    AIService.testOverride = FakeAIServiceImpl();
    final bio = await generateFullBiographyFlexible(
      userName: 'UserX',
      aiName: 'AiX',
      userBirthday: DateTime(1990, 1, 1),
      meetStory: 'Nos conocimos en un foro',
      appearanceGenerator: FakeAppearanceGenerator(),
      userCountryCode: 'ES',
      aiCountryCode: 'JP',
    );

    expect(bio, isNotNull);
    expect(bio.avatar, isNotNull);
    expect(bio.avatar!.url, contains('https://'));
    expect(bio.appearance, isA<Map<String, dynamic>>());
    AIService.testOverride = null;
  });
}
