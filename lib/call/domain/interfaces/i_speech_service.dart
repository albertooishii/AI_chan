import 'dart:typed_data';

/// Interfaz para servicios de síntesis de voz (TTS) específica del dominio call
abstract interface class ISpeechService {
  /// Convierte texto a audio
  Future<Uint8List> textToSpeech({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  });

  /// Obtiene las voces disponibles
  Future<List<String>> getAvailableVoices();

  /// Verifica si el servicio está disponible
  Future<bool> isAvailable();
}

/// Interfaz consolidada para servicios TTS del dominio call (reemplaza ITtsService core)
abstract interface class ICallTtsService {
  /// Genera un archivo de audio para el texto y devuelve la ruta local
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  });

  /// Convierte texto a audio en bytes
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  });

  /// Obtiene las voces disponibles
  Future<List<Map<String, dynamic>>> getAvailableVoices();

  /// Verifica si el servicio está disponible
  Future<bool> isAvailable();

  /// Configura parámetros del servicio
  void configure(final Map<String, dynamic> config);
}

/// Interfaz consolidada para servicios STT del dominio call (reemplaza ISttService core)
abstract interface class ICallSttService {
  /// Transcribe un archivo de audio
  Future<String?> transcribeAudio(final String filePath);

  /// Transcribe archivo con opciones avanzadas
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  });

  /// Procesa audio y retorna texto
  Future<String> processAudio(final Uint8List audioData);

  /// Configura parámetros del servicio
  void configure(final Map<String, dynamic> config);

  /// Verifica si el servicio está disponible
  Future<bool> isAvailable();
}
