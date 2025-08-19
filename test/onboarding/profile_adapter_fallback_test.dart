import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/services/adapters/profile_adapter.dart';
import 'package:ai_chan/services/ai_service.dart';

class ThrowingAIService implements AIService {
  @override
  noSuchMethod(Invocation invocation) => throw Exception('AI failure');
}

void main() {
  test('ProfileAdapter returns fallback profile when AI service throws', () async {
    final adapter = ProfileAdapter(aiService: ThrowingAIService());
    final p = await adapter.generateBiography(
      userName: 'User',
      aiName: 'Ai',
      userBirthday: DateTime(1990),
      meetStory: 'meet',
    );

    expect(p, isNotNull);
    expect(p.biography, isA<Map<String, dynamic>>());
    expect(p.biography['summary'], contains('fallback'));
  });
}
