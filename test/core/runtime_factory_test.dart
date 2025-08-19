import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;

void main() {
  test('getRuntimeAIServiceForModel selects and caches runtimes', () async {
  final a = runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash');
  final b = runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash');
    expect(identical(a, b), true);

    final g = runtime_factory.getRuntimeAIServiceForModel('gpt-5-mini');
    expect(g, isNotNull);
    // Unknown model falls back to OpenAI per implementation
    final unknown = runtime_factory.getRuntimeAIServiceForModel('something-else');
    expect(unknown, isNotNull);
  });
}
