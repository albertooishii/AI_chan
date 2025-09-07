import 'dart:typed_data';

/// Interfaz para servicios de Google Speech del dominio call
/// Maneja conversión de texto a voz y voz a texto usando Google Cloud APIs
abstract interface class IGoogleSpeechService {
  /// Convierte texto a voz usando Google Cloud Text-to-Speech
  Future<Uint8List?> textToSpeech({
    required final String text,
    final String languageCode,
    final String voiceName,
    final String audioEncoding,
    final int sampleRateHertz,
    final bool noCache,
    final bool useCache,
    final double speakingRate,
    final double pitch,
  });

  /// Convierte texto a voz y guarda como archivo
  Future<String?> textToSpeechFile({
    required final String text,
    final String? customFileName,
    final String languageCode,
    final String voiceName,
    final String audioEncoding,
    final int sampleRateHertz,
    final bool noCache,
    final bool useCache,
    final double speakingRate,
    final double pitch,
  });

  /// Convierte voz a texto usando Google Cloud Speech-to-Text
  Future<String?> speechToText({
    required final Uint8List audioData,
    final String languageCode,
    final String audioEncoding,
    final int sampleRateHertz,
    final bool enableAutomaticPunctuation,
  });

  /// Transcribe un archivo de audio desde path
  Future<String?> speechToTextFromFile(
    final String audioFilePath, {
    final String languageCode,
    final String audioEncoding,
    final int sampleRateHertz,
  });

  /// Obtiene la lista de voces disponibles de Google TTS
  Future<List<Map<String, dynamic>>> fetchGoogleVoices({
    final bool forceRefresh,
  });

  /// Obtiene voces que coinciden con los códigos de idioma del usuario y AI
  Future<List<Map<String, dynamic>>> voicesForUserAndAi(
    final List<String> userLanguageCodes,
    final List<String> aiLanguageCodes, {
    final bool forceRefresh,
  });

  /// Obtiene voces Neural/WaveNet para los idiomas especificados
  Future<List<Map<String, dynamic>>> getNeuralWaveNetVoices(
    final List<String> userLanguageCodes,
    final List<String> aiLanguageCodes, {
    final bool forceRefresh,
  });

  /// Obtiene configuración de voz por defecto
  Map<String, dynamic> getVoiceConfig();

  /// Verifica si el servicio está configurado correctamente
  bool get isConfigured;

  /// Limpia el caché de voces
  Future<void> clearVoicesCache();
}
