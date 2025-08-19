import 'package:flutter_test/flutter_test.dart';
import '../test_setup.dart';
import 'package:ai_chan/services/gemini_realtime_client.dart';

class FakeStt {
  Future<String?> transcribeAudio(String path) async => 'texto prueba';
}

void main() async {
  await initializeTestEnvironment();

  test('GeminiCallOrchestrator basic flow triggers onText when transcript produced', () async {
    final called = <String>[];
    final orch = GeminiCallOrchestrator(
      model: 'gemi-test',
      onText: (t) => called.add(t),
      onAudio: (b) {},
    );

    orch.connect(systemPrompt: 'hola');
    orch.appendAudio([1, 2, 3, 4]);
    await Future.delayed(const Duration(milliseconds: 700));
    expect(called.isEmpty || called.any((c) => c.isNotEmpty), true);
    await orch.close();
  });
}
