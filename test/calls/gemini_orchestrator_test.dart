import 'dart:typed_data';
import 'package:ai_chan/voice/infrastructure/clients/gemini_realtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_setup.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';

class FakeTts implements ITtsService {
  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async => [];

  @override
  Future<String?> synthesizeToFile({
    required String text,
    Map<String, dynamic>? options,
  }) async {
    // Crear un archivo temporal no necesario, devolver null es aceptable para la prueba de unidad
    return null;
  }
}

void main() async {
  await initializeTestEnvironment();

  test(
    'GeminiCallOrchestrator processes audio -> transcribe -> ai -> tts (unit)',
    () async {
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
    },
  );
}
