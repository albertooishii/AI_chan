import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_stt_service.dart';

class _FakeTestStt implements ISttService {
  @override
  Future<String?> transcribeAudio(String path) async =>
      'transcripcion de prueba';
}

Future<void> initializeTestEnvironment({
  Map<String, Object>? prefs,
  String? dotenvContents,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ensure tests run with minimal noisy logging
  Config.setOverrides({'APP_LOG_LEVEL': 'error'});
  if (dotenvContents != null) {
    await Config.initialize(dotenvContents: dotenvContents);
  } else {
    await Config.initialize();
  }
  SharedPreferences.setMockInitialValues(prefs ?? {});
  // Override STT to avoid hitting GoogleSpeechService in tests
  di.setTestSttOverride(_FakeTestStt());
}
