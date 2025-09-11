import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';
import 'test_utils/prefs_test_utils.dart';
import 'fakes/fake_connectors.dart' as fake_connectors;
import 'fakes/fake_http_client.dart';
import 'package:ai_chan/core/http_connector.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/provider_registration.dart';

/// 🧪 Test Environment Setup
/// Configuración global para tests con servicios mock
void setupTestEnvironment() {
  // Compatibility function for legacy tests
}

Future<void> initializeTestEnvironment({
  final Map<String, Object>? prefs,
  final String? dotenvContents,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚡ ACELERAR TESTS: Desactivar delays en retries
  AIProviderConfigLoader.skipEnvironmentValidation = true;

  // Create a central temporary base directory for ai_chan tests under systemTemp
  final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
  if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);

  // Create temporary directories for image/audio/cache tests inside the central folder
  final suffix = DateTime.now().millisecondsSinceEpoch;
  final tmpImageDir = Directory('${baseTmp.path}/images_$suffix')
    ..createSync(recursive: true);
  final tmpAudioDir = Directory('${baseTmp.path}/audio_$suffix')
    ..createSync(recursive: true);
  final tmpCacheDir = Directory('${baseTmp.path}/cache_$suffix')
    ..createSync(recursive: true);

  Config.setOverrides({
    'DEBUG_MODE': 'off',
    'TEST_IMAGE_DIR': tmpImageDir.path,
    'TEST_AUDIO_DIR': tmpAudioDir.path,
    'TEST_CACHE_DIR': tmpCacheDir.path,
  });

  // Provide test environment with required default models and ALL API keys for tests
  final testDotenvContents =
      dotenvContents ??
      '''
DEFAULT_TEXT_MODEL=gemini-1.5-flash-latest
DEFAULT_IMAGE_MODEL=gemini-1.5-flash-latest
OPENAI_API_KEYS=["test_openai_key_1", "test_openai_key_2"]
GEMINI_API_KEYS=["test_gemini_key_1", "test_gemini_key_2"]
GROK_API_KEYS=["test_grok_key_1"]
GOOGLE_CLOUD_API_KEY=test_google_cloud_key
ANTHROPIC_API_KEY=test_anthropic_key
MISTRAL_API_KEY=test_mistral_key
''';

  await Config.initialize(dotenvContents: testDotenvContents);

  // ✅ PROVIDERS: Inicializar sistema de providers para tests
  registerAllProviders();

  // Initialize SharedPreferences with centralized test helper for consistency
  PrefsTestUtils.setMockInitialValues(prefs);

  // 🔥 Legacy test compatibility functions (no-op)
  // Call tests were eliminated, these are just stubs

  // Register fake connectors to ensure no tests open real sockets/websockets
  fake_connectors.registerFakeSocketConnector();
  fake_connectors.registerFakeWebSocketConnector();

  // Install fake HTTP client to avoid network calls in tests
  final fakeHttp = FakeHttpClient();
  HttpConnector.setClient(fakeHttp);
}
