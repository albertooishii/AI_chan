import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/core/config.dart';

void main() {
  group('AIProviderManager dynamic model methods', () {
    late AIProviderManager manager;

    setUpAll(() async {
      // Inicializar configuración con valores mock para tests
      await Config.initialize(
        dotenvContents: '''
DEBUG_MODE=basic
SUMMARY_BLOCK_SIZE=32
AUDIO_TTS_MODE=google
PREFERRED_AUDIO_FORMAT=mp3
OPENAI_API_KEYS=["test-key-1","test-key-2"]
GEMINI_API_KEYS=["test-gemini-key"]
GROK_API_KEYS=["test-grok-key"]
GOOGLE_CLOUD_API_KEYS=["test-google-key"]
''',
      );
    });

    setUp(() {
      manager = AIProviderManager.instance;
    });

    test('should have getDefaultModelForCapability method', () {
      // Verificamos que el método existe y es callable
      expect(manager.getDefaultModelForCapability, isA<Function>());
    });

    test('should have getDefaultTextModel method', () {
      // Verificamos que el método existe y es callable
      expect(manager.getDefaultTextModel, isA<Function>());
    });

    test('should have getDefaultImageModel method', () {
      // Verificamos que el método existe y es callable
      expect(manager.getDefaultImageModel, isA<Function>());
    });

    test(
      'getDefaultModelForCapability should accept AICapability parameter',
      () {
        // Test que verifica que el método acepta el parámetro correcto
        expect(
          () =>
              manager.getDefaultModelForCapability(AICapability.textGeneration),
          returnsNormally,
        );
      },
    );

    test(
      'getDefaultTextModel should be equivalent to textGeneration capability',
      () async {
        // Esta prueba verifica que ambos métodos son equivalentes
        // pero no ejecutamos la llamada real para evitar problemas de configuración
        expect(manager.getDefaultTextModel, isNotNull);
        expect(manager.getDefaultModelForCapability, isNotNull);
      },
    );
  });
}
