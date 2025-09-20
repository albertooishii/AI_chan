/// 🎯 DDD: Puerto para reconocimiento de voz (STT) - Versión avanzada
abstract interface class ISttService {
  /// Iniciar escucha en tiempo real
  Stream<RecognitionResult> startListening({
    required final String language,
    final bool enablePartialResults = true,
  });

  /// Detener escucha
  Future<void> stopListening();

  /// Reconocer audio desde datos
  Future<RecognitionResult> recognizeAudio({
    required final List<int> audioData,
    required final String language,
    final String format = 'wav',
  });

  /// Verificar disponibilidad
  Future<bool> isAvailable();

  /// Idiomas soportados
  Future<List<String>> getSupportedLanguages();

  /// ¿Está escuchando actualmente?
  bool get isListening;

  /// Transcribe an audio file at [filePath] and return the transcription text or null on failure.
  /// (Método legacy mantenido para compatibilidad)
  Future<String?> transcribeAudio(final String filePath);

  /// Extended version with options for advanced use cases
  /// (Método legacy mantenido para compatibilidad)
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}

/// 🎯 DDD: Resultado de reconocimiento de voz
class RecognitionResult {
  const RecognitionResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    required this.duration,
  });

  final String text;
  final double confidence;
  final bool isFinal;
  final Duration duration;

  @override
  String toString() =>
      'RecognitionResult("$text", confidence: $confidence, final: $isFinal)';
}
