import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/services/adapters/profile_adapter.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import '../test_setup.dart';

// Fake implementation to avoid network calls in unit tests
class FakeAIService implements AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    if (enableImageGeneration) {
      const onePixelPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      return AIResponse(text: '', base64: onePixelPngBase64, seed: 'fake-seed', prompt: 'fake-prompt');
    }
    return AIResponse(text: '{}', base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-model'];

}

void main() {
  test('GoogleProfileAdapter returns a basic profile and appearance', () async {
    await initializeTestEnvironment();
    AIService.testOverride = FakeAIService();
  final adapter = ProfileAdapter(aiService: AIService.testOverride!);

    final now = DateTime(1990, 1, 1);
    final profile = await adapter.generateBiography(
      userName: 'User',
      aiName: 'AiChan',
      userBirthday: now,
      meetStory: 'A test meet',
    );
    expect(profile, isA<AiChanProfile>());
    expect(profile.userName, 'User');

    final image = await adapter.generateAppearance(profile);
    expect(image, isA<AiImage>());
    expect(image!.url, contains('example.com'));
  });
}
