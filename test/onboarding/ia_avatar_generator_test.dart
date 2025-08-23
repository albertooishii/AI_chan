import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import '../test_setup.dart';

class FakeImageAIService extends AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    // Return a 1x1 PNG base64 (valid)
    const onePixelPngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
    return AIResponse(text: '', base64: onePixelPngBase64, seed: 'seed-123', prompt: 'prompt-xyz');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-image'];
}

void main() {
  test('IAAvatarGenerator genera y guarda imagen correctamente', () async {
    await initializeTestEnvironment();

    final profile = AiChanProfile(
      userName: 'User',
      aiName: 'Ai',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final fake = FakeImageAIService();
    final generator = IAAvatarGenerator();

    // Fake saver that verifies base64 prefix and returns filename
    Future<String?> fakeSaver(String base64, {String prefix = 'ai_avatar'}) async {
      expect(base64.startsWith('iVBORw0KGgo'), isTrue);
      return '${prefix}_test.png';
    }

    final appearance = <String, dynamic>{'edad_aparente': 25};

    final image = await generator.generateAvatarFromAppearance(
      profile,
      appearance,
      aiService: fake,
      saveImageFunc: fakeSaver,
    );

    expect(image, isA<AiImage>());
    expect(image.seed, equals('seed-123'));
    expect(image.prompt, equals('prompt-xyz'));
    expect(image.url, equals('ai_avatar_test.png'));
  });
}
