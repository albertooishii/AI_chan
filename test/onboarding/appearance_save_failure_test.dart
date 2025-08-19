import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/services/ai_service.dart';
import '../test_setup.dart';

class FakeBadImageAIService extends AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    // Respuesta con JSON vacío y base64 corrupto
    return AIResponse(text: '{}', base64: 'not_base64!!!', seed: 's', prompt: 'p');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake'];
}

void main() {
  test('IAAppearanceGenerator lanza si guardar imagen falla (base64 inválido)', () async {
    await initializeTestEnvironment(
      dotenvContents: 'DEFAULT_TEXT_MODEL=fake\nDEFAULT_IMAGE_MODEL=fake',
    );
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
  final fake = FakeBadImageAIService();

  // Inyectar override global del AIService para que Chat/Generator lo use
  AIService.testOverride = fake;
  expect(() async => await gen.generateAppearancePromptWithImage(profile, aiService: null), throwsA(isA<Exception>()));
  AIService.testOverride = null;
  });
}
