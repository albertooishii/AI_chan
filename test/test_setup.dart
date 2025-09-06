import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';
import 'test_utils/prefs_test_utils.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'fakes/fake_connectors.dart' as fake_connectors;
import 'fakes/fake_http_client.dart';
import 'fakes/fake_audio_playback.dart';
import 'package:ai_chan/core/http_connector.dart';

// (No global fake realtime client here — tests opt-in to install fakes
// using `di.setTestRealtimeClientFactory(...)` when they need to.)

class _FakeTestStt implements ISttService {
  @override
  Future<String?> transcribeAudio(final String filePath) async {
    return 'fake transcription for testing';
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}

Future<void> initializeTestEnvironment({
  final Map<String, Object>? prefs,
  final String? dotenvContents,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ensure tests run with minimal noisy logging
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

  // Provide test environment with required default models
  final testDotenvContents =
      dotenvContents ??
      '''
DEFAULT_TEXT_MODEL=gemini-1.5-flash-latest
DEFAULT_IMAGE_MODEL=gemini-1.5-flash-latest
GEMINI_API_KEY=test_key
''';

  await Config.initialize(dotenvContents: testDotenvContents);
  // Initialize SharedPreferences with centralized test helper for consistency
  // (tests can override by passing prefs)
  PrefsTestUtils.setMockInitialValues(prefs);
  // Override STT to avoid hitting GoogleSpeechService in tests
  di.setTestSttOverride(_FakeTestStt());
  // Override audio playback to avoid native plugin initialization in tests
  di.setTestAudioPlaybackOverride(FakeAudioPlayback());
  // Register fake connectors to ensure no tests open real sockets/websockets
  fake_connectors.registerFakeSocketConnector();
  fake_connectors.registerFakeWebSocketConnector();

  // Install fake HTTP client to avoid network calls in tests
  final fakeHttp = FakeHttpClient();
  // Optionally tests may customize fakeHttp.when(...) per-test
  HttpConnector.setClient(fakeHttp);
}
