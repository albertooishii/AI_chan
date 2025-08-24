import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
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
      return AIResponse(text: '', base64: onePixelPngBase64, seed: 'fake-seed', prompt: 'fake-prompt');
    }
    // Default simple JSON response for profile/appearance generation
    final json = '{"resumen_breve":"Resumen de prueba","datos_personales":{"nombre_completo":"Ai Test"}}';
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
      return AIResponse(text: '', base64: onePixelPngBase64, seed: 'fake-seed', prompt: 'fake-prompt');
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
    await initializeTestEnvironment(
      dotenvContents:
          'DEFAULT_TEXT_MODEL=gemini-1.5-flash-latest\nDEFAULT_IMAGE_MODEL=gemini-1.5-flash-latest\nIMAGE_DIR_DESKTOP=/tmp/ai_chan_test_images\nGEMINI_API_KEY=test_key\n',
    );
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
    final appearance = await generator.generateAppearancePrompt(profile, aiService: AIService.testOverride!);
    final updatedProfile = profile.copyWith(appearance: appearance);
    final image = await IAAvatarGenerator().generateAvatarFromAppearance(
      updatedProfile,
      aiService: AIService.testOverride!,
    );
    expect(image, isA<AiImage>());
    expect(image.url, contains('.png'));
    // Clear override
    AIService.testOverride = null;
  });
}
