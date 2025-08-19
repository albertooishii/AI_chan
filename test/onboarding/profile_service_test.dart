import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/services/adapters/universal_profile_service_adapter.dart';
import 'package:ai_chan/services/ai_service.dart';

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
    final json = '''{
"datos_personales": {"nombre_completo": "Ai Test", "fecha_nacimiento": "1999-01-01"},
"personalidad": {"valores": {"Sociabilidad": "5"}, "descripcion": {}},
"resumen_breve": "Resumen de prueba",
"historia_personal": []
}''';
    return AIResponse(text: json, base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-model'];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await dotenv.load();
    AIService.testOverride = FakeAIService();
  });

  test('ProfileService (antes OpenAI) funciona con adaptador universal y fake', () async {
    final adapter = UniversalProfileServiceAdapter();

    final profile = await adapter.generateBiography(
      userName: 'UserX',
      aiName: 'AiX',
      userBirthday: DateTime(1990, 1, 1),
      meetStory: 'Historia',
      userCountryCode: 'ES',
      aiCountryCode: 'JP',
    );
    expect(profile, isA<AiChanProfile>());
    expect(profile.userName, 'UserX');
    expect(profile.aiName, 'AiX');
    expect(profile.biography, isNotEmpty);

    final avatar = await adapter.generateAppearance(profile);
    expect(avatar, isA<AiImage>());
    expect(avatar?.url, isNotEmpty);
  });
}
