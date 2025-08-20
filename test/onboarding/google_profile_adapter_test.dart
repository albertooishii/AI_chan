import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import '../test_setup.dart';

// Local minimal base fake for image-capable tests
class BaseFakeAIService implements AIService {
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
      return AIResponse(
        text: '',
        base64: onePixelPngBase64,
        seed: 'fake-seed',
        prompt: 'fake-prompt',
      );
    }
    // Default simple JSON response for profile/appearance generation
    final json =
        '{"resumen_breve":"Resumen de prueba","datos_personales":{"nombre_completo":"Ai Test"}}';
    return AIResponse(text: json, base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-model'];
}

// Local fake that delegates to the shared fake but returns a 1x1 PNG base64 for
// image-generation requests so the appearance generator can proceed in unit tests.
class LocalImageFake extends BaseFakeAIService {
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
      return AIResponse(
        text: '',
        base64: onePixelPngBase64,
        seed: 'fake-seed',
        prompt: 'fake-prompt',
      );
    }
    return super.sendMessageImpl(
      history,
      systemPrompt,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );
  }
}

void main() {
  test('GoogleProfileAdapter returns a basic profile and appearance', () async {
    await initializeTestEnvironment();
    // Use the top-level LocalImageFake declared above.
    AIService.testOverride = LocalImageFake();
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

    // Exercise the image-generation path directly and inject a saveImageFunc to avoid
    // filesystem dependencies and adapter fallback to placeholder. This makes the test
    // fail if the generator didn't produce an image (avoids false positives).
    final generator = IAAppearanceGenerator();
    final res = await generator.generateAppearancePromptWithImage(
      profile,
      aiService: AIService.testOverride!,
      saveImageFunc: (String base64, {String prefix = 'ai_avatar'}) async {
        // Do not write to disk in unit tests; return a deterministic filename.
        return 'fake_image.png';
      },
    );
    final image = res['avatar'] as AiImage?;
    expect(image, isA<AiImage>());
    expect(image!.url, equals('fake_image.png'));
    // Clear override
    AIService.testOverride = null;
  });
}
