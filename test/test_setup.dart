import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'fakes/fake_connectors.dart' as fake_connectors;
import 'fakes/fake_http_client.dart';
import 'package:ai_chan/core/http_connector.dart';

// (No global fake realtime client here — tests opt-in to install fakes
// using `di.setTestRealtimeClientFactory(...)` when they need to.)

class _FakeTestStt implements ISttService {
  @override
  Future<String?> transcribeAudio(String path) async => 'transcripcion de prueba';
}

Future<void> initializeTestEnvironment({Map<String, Object>? prefs, String? dotenvContents}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ensure tests run with minimal noisy logging
  Config.setOverrides({'APP_LOG_LEVEL': 'error'});

  // Provide test environment with required default models
  final testDotenvContents =
      dotenvContents ??
      '''
DEFAULT_TEXT_MODEL=gemini-1.5-flash-latest
DEFAULT_IMAGE_MODEL=gemini-1.5-flash-latest
GEMINI_API_KEY=test_key
''';

  await Config.initialize(dotenvContents: testDotenvContents);
  SharedPreferences.setMockInitialValues(prefs ?? {});
  // Override STT to avoid hitting GoogleSpeechService in tests
  di.setTestSttOverride(_FakeTestStt());
  // Register fake connectors to ensure no tests open real sockets/websockets
  fake_connectors.registerFakeSocketConnector();
  fake_connectors.registerFakeWebSocketConnector();

  // Install fake HTTP client to avoid network calls in tests
  final fakeHttp = FakeHttpClient();
  // Optionally tests may customize fakeHttp.when(...) per-test
  HttpConnector.setClient(fakeHttp);
}
