import 'dart:typed_data';

/// Interfaz para servicios de detección de actividad de voz (Voice Activity Detector)
/// del dominio call
abstract interface class IVadService {
  /// Alimenta datos de audio PCM16LE mono al detector VAD
  /// Emite callbacks onSpeechStart/onSpeechEnd cuando detecta cambios de estado
  void feed(final Uint8List pcm16Bytes);

  /// Configura los callbacks para eventos de detección de voz
  void setCallbacks({
    final void Function()? onSpeechStart,
    final void Function()? onSpeechEnd,
  });

  /// Configura parámetros del detector VAD
  void configure({final double? thresholdRms, final int? silenceMs});

  /// Libera recursos del detector VAD
  void dispose();

  /// Verifica si el servicio está disponible
  Future<bool> isAvailable();
}
