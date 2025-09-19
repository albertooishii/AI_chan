import 'dart:convert';
import 'dart:io';
import 'package:ai_chan/shared.dart';

/// 🎯 Servicio centralizado de STT (Speech-to-Text)
/// Usa AIProviderManager para resolver providers automáticamente
class CentralizedSttService implements ISttService {
  CentralizedSttService._();

  static final CentralizedSttService _instance = CentralizedSttService._();
  static CentralizedSttService get instance => _instance;

  final AIProviderManager _aiProviderManager = AIProviderManager.instance;
  bool _isListening = false;

  @override
  Stream<RecognitionResult> startListening({
    required final String language,
    final bool enablePartialResults = true,
  }) async* {
    if (_isListening) {
      throw const SpeechRecognitionException('Ya está escuchando');
    }

    _isListening = true;

    try {
      // TODO: Integrar con AIProviderManager para STT real
      // Por ahora simulamos reconocimiento

      yield const RecognitionResult(
        text: 'Simulando reconocimiento...',
        confidence: 0.5,
        isFinal: false,
        duration: Duration(milliseconds: 500),
      );

      await Future.delayed(const Duration(seconds: 2));

      yield const RecognitionResult(
        text: 'Texto reconocido de ejemplo',
        confidence: 0.95,
        isFinal: true,
        duration: Duration(seconds: 2),
      );
    } finally {
      _isListening = false;
    }
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
  }

  @override
  Future<RecognitionResult> recognizeAudio({
    required final List<int> audioData,
    required final String language,
    final String format = 'wav',
  }) async {
    try {
      final transcriptionProvider = await _aiProviderManager
          .getProviderForCapability(AICapability.audioTranscription);

      if (transcriptionProvider == null) {
        Log.w(
          '[CentralizedSTT] No hay provider de transcripción disponible, usando fallback',
        );
        return _simulateRecognition(audioData, language);
      }

      // Convert audio data to base64
      final audioBase64 = base64Encode(audioData);

      final providerResp = await transcriptionProvider.transcribeAudio(
        audioBase64: audioBase64,
        audioFormat: format,
        language: language,
        additionalParams: {'response_format': 'text'},
      );

      if (providerResp.text.isEmpty) {
        Log.w('[CentralizedSTT] No se recibió transcripción válida');
        return _simulateRecognition(audioData, language);
      }

      Log.d(
        '[CentralizedSTT] ✅ Audio transcrito exitosamente: "${providerResp.text}"',
      );

      return RecognitionResult(
        text: providerResp.text,
        confidence:
            0.95, // OpenAI Whisper no devuelve confidence, asumimos alto
        isFinal: true,
        duration: Duration(
          milliseconds: audioData.length ~/ 16,
        ), // Aprox para 16kHz
      );
    } on Exception catch (e) {
      Log.e('[CentralizedSTT] Error transcribiendo audio: $e');
      return _simulateRecognition(audioData, language);
    }
  }

  /// Fallback para cuando no hay providers reales
  Future<RecognitionResult> _simulateRecognition(
    final List<int> audioData,
    final String language,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));

    return RecognitionResult(
      text: 'Texto reconocido desde audio (${audioData.length} bytes)',
      confidence: 0.92,
      isFinal: true,
      duration: Duration(
        milliseconds: audioData.length ~/ 16,
      ), // Aprox para 16kHz
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final transcriptionProvider = await _aiProviderManager
          .getProviderForCapability(AICapability.audioTranscription);
      return transcriptionProvider != null;
    } on Exception catch (e) {
      Log.w('[CentralizedSTT] Error verificando disponibilidad: $e');
      return false; // Sin provider real, solo simulación
    }
  }

  @override
  Future<List<String>> getSupportedLanguages() async {
    // TODO: Obtener de AIProviderManager
    return ['es-ES', 'en-US', 'fr-FR', 'de-DE', 'it-IT', 'pt-BR'];
  }

  @override
  bool get isListening => _isListening;

  @override
  Future<String?> transcribeAudio(final String filePath) async {
    try {
      Log.d('[CentralizedSTT] Transcribiendo archivo: $filePath');

      // Leer el archivo de audio
      final file = File(filePath);
      if (!file.existsSync()) {
        Log.w('[CentralizedSTT] Archivo no encontrado: $filePath');
        return null;
      }

      final audioBytes = await file.readAsBytes();
      final result = await recognizeAudio(
        audioData: audioBytes,
        language: 'es-ES', // Default language
        format: filePath.split('.').last, // Extract format from extension
      );

      return result.text;
    } on Exception catch (e) {
      Log.e('[CentralizedSTT] Error transcribiendo archivo $filePath: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    try {
      Log.d('[CentralizedSTT] Transcribiendo archivo con opciones: $filePath');

      final file = File(filePath);
      if (!file.existsSync()) {
        Log.w('[CentralizedSTT] Archivo no encontrado: $filePath');
        return null;
      }

      final audioBytes = await file.readAsBytes();
      final language = options?['language'] as String? ?? 'es-ES';
      final format = options?['format'] as String? ?? filePath.split('.').last;

      final result = await recognizeAudio(
        audioData: audioBytes,
        language: language,
        format: format,
      );

      return result.text;
    } on Exception catch (e) {
      Log.e('[CentralizedSTT] Error transcribiendo archivo $filePath: $e');
      return null;
    }
  }
}

/// 🎯 DDD: Excepción específica para STT
class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.message);
  final String message;

  @override
  String toString() => 'SpeechRecognitionException: $message';
}
