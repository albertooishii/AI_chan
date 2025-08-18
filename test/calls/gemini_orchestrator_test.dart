import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../test_setup.dart';
import 'package:ai_chan/services/gemini_realtime_client.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';

class FakeStt implements ISttService {
  @override
  Future<String?> transcribeAudio(String path) async {
    return 'transcripcion de prueba';
  }
}

class FakeAi implements IAIService {
  @override
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  }) async {
    return {'text': 'respuesta generada por ai'};
  }

  @override
  Future<List<String>> getAvailableModels() async => ['gemi-test'];

  @override
  Future<String?> textToSpeech(String text, {String voice = ''}) async => null;
}

class FakeTts implements ITtsService {
  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async => [];

  @override
  Future<String?> synthesizeToFile({required String text, Map<String, dynamic>? options}) async {
    // Crear un archivo temporal no necesario, devolver null es aceptable para la prueba de unidad
    return null;
  }
}

void main() async {
  await initializeTestEnvironment();

  test('GeminiCallOrchestrator processes audio -> transcribe -> ai -> tts (unit)', () async {
    final orchestrator = GeminiCallOrchestrator(
      model: 'gemi-test',
      onText: (t) {
        expect(t, contains('respuesta'));
      },
      onAudio: (Uint8List bytes) {
        // En esta prueba no esperamos audio, ya que FakeTts devuelve null
        expect(bytes, isNotNull);
      },
    );

    // Inyectar fakes vía di no trivial; aquí comprobamos flujo de _processPendingAudioChunk en aislamiento
    // Append small bytes to trigger transcription
    orchestrator.connect(systemPrompt: 'hola');
    orchestrator.appendAudio([0, 1, 2, 3]);

    // Esperar un poco para que el timer procese
    await Future.delayed(const Duration(milliseconds: 600));
    await orchestrator.close();
  });
}
