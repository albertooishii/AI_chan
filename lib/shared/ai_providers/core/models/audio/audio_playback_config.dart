/// 🎵 Configuración para reproducción de audio
class AudioPlaybackConfig {
  const AudioPlaybackConfig({
    this.volume = 1.0,
    this.speed = 1.0,
    this.autoPlay = true,
    this.cleanupTempFiles = true,
    this.notifyOnCompletion = true,
    this.fallbackDurationEstimate = true,
  });

  /// Volumen de reproducción (0.0 - 1.0)
  final double volume;

  /// Velocidad de reproducción
  final double speed;

  /// Reproducir automáticamente al cargar
  final bool autoPlay;

  /// Limpiar archivos temporales automáticamente
  final bool cleanupTempFiles;

  /// Notificar cuando termine la reproducción
  final bool notifyOnCompletion;

  /// Usar estimación de duración como fallback
  final bool fallbackDurationEstimate;

  /// Configuración por defecto
  static const AudioPlaybackConfig defaultConfig = AudioPlaybackConfig();

  /// Crear copia con modificaciones
  AudioPlaybackConfig copyWith({
    final double? volume,
    final double? speed,
    final bool? autoPlay,
    final bool? cleanupTempFiles,
    final bool? notifyOnCompletion,
    final bool? fallbackDurationEstimate,
  }) => AudioPlaybackConfig(
    volume: volume ?? this.volume,
    speed: speed ?? this.speed,
    autoPlay: autoPlay ?? this.autoPlay,
    cleanupTempFiles: cleanupTempFiles ?? this.cleanupTempFiles,
    notifyOnCompletion: notifyOnCompletion ?? this.notifyOnCompletion,
    fallbackDurationEstimate:
        fallbackDurationEstimate ?? this.fallbackDurationEstimate,
  );

  @override
  String toString() => 'AudioPlaybackConfig(volume: $volume, speed: $speed)';
}
