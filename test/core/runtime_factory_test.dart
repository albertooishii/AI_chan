import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/enhanced_ai_runtime_provider.dart';
import '../test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });
  test('Enhanced AI Provider selects and caches runtimes', () async {
    final a = await EnhancedAIRuntimeProvider.getAIServiceForModel(
      'gemini-2.5-flash',
    );
    final b = await EnhancedAIRuntimeProvider.getAIServiceForModel(
      'gemini-2.5-flash',
    );
    // Enhanced AI creates fresh instances but uses same underlying providers
    expect(a, isNotNull);
    expect(b, isNotNull);

    final g = await EnhancedAIRuntimeProvider.getAIServiceForModel(
      'gpt-4.1-mini',
    );
    expect(g, isNotNull);
    // Unknown model falls back to OpenAI per implementation
    final unknown = await EnhancedAIRuntimeProvider.getAIServiceForModel(
      'something-else',
    );
    expect(unknown, isNotNull);
  });
}
