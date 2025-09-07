import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/call/infrastructure/services/openai_realtime_client.dart';
import 'package:ai_chan/call/infrastructure/services/gemini_realtime_client.dart';
import 'package:ai_chan/core/di_test_bootstrap.dart' as di_test_bootstrap;
import '../test_setup.dart' as test_setup;

void main() {
  setUpAll(() async {
    // Provide both Gemini defaults and OpenAI keys for the OpenAI client constructor
    await test_setup.initializeTestEnvironment(
      dotenvContents: '''
DEFAULT_TEXT_MODEL=gemini-1.5-flash-latest
DEFAULT_IMAGE_MODEL=gemini-1.5-flash-latest
GEMINI_API_KEY=test_key
OPENAI_REALTIME_MODEL=gpt-realtime
OPENAI_API_KEY=test_openai_key
''',
    );
    di_test_bootstrap.registerDefaultRealtimeFactoriesForTest();
  });

  test('DI default realtime factories resolve to expected implementations', () {
    final openaiClient = di.getRealtimeClientForProvider('openai');
    final geminiClient = di.getRealtimeClientForProvider('gemini');
    final googleClient = di.getRealtimeClientForProvider('google');

    expect(openaiClient, isA<OpenAIRealtimeClient>());
    expect(geminiClient, isA<GeminiRealtimeClient>());
    expect(googleClient, isA<GeminiRealtimeClient>());
  });
}
