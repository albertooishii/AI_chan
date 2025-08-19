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
    // Devuelve un JSON de biografía mínimo válido para que el generador lo acepte
    // Si se solicita generación de imágenes, devolver un base64 PNG 1x1 y seed
    if (enableImageGeneration) {
      const onePixelPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      return AIResponse(text: '', base64: onePixelPngBase64, seed: 'fake-seed', prompt: 'fake-prompt');
    }

    final json = '''{
"datos_personales": {"nombre_completo": "Test AI", "fecha_nacimiento": "1999-01-01"},
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
    // Inyectar servicio IA fake para tests (evita llamadas HTTP reales)
    AIService.testOverride = FakeAIService();
  });

  test('UniversalProfileServiceAdapter genera biografía y apariencia correctamente', () async {
    final adapter = UniversalProfileServiceAdapter();

    final profile = await adapter.generateBiography(
      userName: 'UserTest',
      aiName: 'AiTest',
      userBirthday: DateTime(1992, 3, 15),
      meetStory: 'Historia de prueba',
      userCountryCode: 'ES',
      aiCountryCode: 'JP',
    );
    expect(profile, isA<AiChanProfile>());
    expect(profile.userName, 'UserTest');
    expect(profile.aiName, 'AiTest');
    expect(profile.biography, isNotEmpty);

    final avatar = await adapter.generateAppearance(profile);
    expect(avatar, isA<AiImage>());
    expect(avatar?.url, isNotEmpty);
  });
}
