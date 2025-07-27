import 'package:flutter/foundation.dart';
import 'openai_service.dart';

/// Controlador para llamadas de voz automáticas con OpenAI Realtime API
class VoiceCallController {
  final OpenAIService openAIService;

  VoiceCallController({required this.openAIService});

  /// Inicia la llamada de voz en tiempo real grabando siempre desde el micrófono
  Future<void> startCall({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required void Function(String textChunk) onText,
    void Function(String reasoning)? onReasoning,
    void Function(String summary)? onSummary,
    void Function()? onDone,
    String model = 'gpt-4o-realtime-preview',
    String audioFormat = 'wav',
    required Future<Uint8List> Function() grabarAudioMicrofono,
  }) async {
    try {
      // Grabar audio del micrófono
      final audioBytes = await grabarAudioMicrofono();
      // Filtrar historial para excluir mensajes 'system' y asegurar formato correcto
      final filteredHistory = history
          .where((msg) => msg['role'] != 'system' && msg['role'] != null && msg['content'] != null)
          .map((msg) => {'role': msg['role']!, 'content': msg['content']!})
          .toList();
      await openAIService.startRealtimeCall(
        systemPrompt: systemPrompt,
        history: filteredHistory,
        onText: onText,
        onReasoning: onReasoning,
        onSummary: onSummary,
        onDone: onDone,
        model: model,
        audioBytes: audioBytes,
        audioFormat: audioFormat,
      );
    } catch (e) {
      debugPrint('Error en llamada de voz: $e');
      if (onDone != null) onDone();
    }
  }
}
