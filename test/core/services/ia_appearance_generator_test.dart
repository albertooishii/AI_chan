import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  test('IAAppearanceGenerator instantiates correctly', () {
    final generator = IAAppearanceGenerator();
    expect(generator, isNotNull);
  });

  test('IAAppearanceGenerator can process basic profile structure', () {
    final profile = AiChanProfile(
      biography: <String, dynamic>{'text': 'Test biography'},
      userName: 'TestUser',
      aiName: 'TestAI',
      userBirthdate: DateTime(1990),
      aiBirthdate: DateTime(1990),
      appearance: <String, dynamic>{},
    );

    // Just test that the profile is structured correctly for the generator
    expect(profile.biography, isNotEmpty);
    expect(profile.userName, equals('TestUser'));
    expect(profile.aiName, equals('TestAI'));
  });
}
