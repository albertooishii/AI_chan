/// Interfaz para servicios de tonos y efectos sonoros
abstract interface class IToneService {
  /// Reproduce tono de colgado o error
  Future<void> playHangupOrErrorTone({
    final int sampleRate = 24000,
    final int durationMs = 350,
    final String preset = 'melodic',
  });

  /// Reproduce un tono personalizado
  Future<void> playCustomTone({
    required final double frequency,
    required final int durationMs,
    final double volume = 1.0,
  });

  /// Reproduce un sweep de frecuencias
  Future<void> playFrequencySweep({
    required final double startFreq,
    required final double endFreq,
    required final int durationMs,
    final double volume = 1.0,
  });

  /// Detiene cualquier reproducción en curso
  Future<void> stop();

  /// Verifica si el servicio está disponible
  Future<bool> isAvailable();
}
