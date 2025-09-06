import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import '../test_setup.dart';

class ThrowingAIService implements AIService {
  @override
  noSuchMethod(final Invocation invocation) => throw Exception('AI failure');
}

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });
  test(
    'ProfileAdapter returns fallback profile when AI service throws',
    () async {
      final adapter = ProfileAdapter(aiService: ThrowingAIService());
      final p = await adapter.generateBiography(
        userName: 'User',
        aiName: 'Ai',
        userBirthdate: DateTime(1990),
        meetStory: 'meet',
      );

      expect(p, isNotNull);
      expect(p.biography, isA<Map<String, dynamic>>());
      expect(p.biography['summary'], contains('fallback'));
    },
  );
}
