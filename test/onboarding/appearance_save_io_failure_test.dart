import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import '../test_setup.dart';

class FakeGoodAIService extends AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    // Devuelve JSON mínimo y base64 válido (pero el saver fallará)
    return AIResponse(text: '{"resumen":"x"}', base64: 'iVBORw0KGgoAAAANSUhEUgAAAAUA', seed: 's', prompt: 'p');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake'];
}

void main() {
  test('IAAppearanceGenerator propaga excepción cuando saveImageFunc lanza', () async {
    await initializeTestEnvironment(dotenvContents: 'DEFAULT_TEXT_MODEL=fake\nDEFAULT_IMAGE_MODEL=fake');

    final profile = AiChanProfile(
      userName: 'u',
      aiName: 'a',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final gen = IAAppearanceGenerator();
    final fake = FakeGoodAIService();

    // Esperamos que la excepción se propague cuando intentamos guardar la imagen
    final appearance = await gen.generateAppearancePrompt(profile, aiService: fake);
    final updatedProfile = profile.copyWith(appearance: appearance);
    expect(() async {
      AIService.testOverride = fake;
      try {
        await IAAvatarGenerator().generateAvatarFromAppearance(updatedProfile);
      } finally {
        AIService.testOverride = null;
      }
    }, throwsA(isA<Exception>()));
  });
}
