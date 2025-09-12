/// 🎵 Resultado de reproducción de audio con información detallada
class AudioPlaybackResult {
  /// Constructor para resultado exitoso
  factory AudioPlaybackResult.success({
    required final Duration duration,
    final String? filePath,
    final Map<String, dynamic>? metadata,
  }) => AudioPlaybackResult(
    success: true,
    duration: duration,
    filePath: filePath,
    metadata: metadata,
  );

  /// Constructor para resultado con error
  factory AudioPlaybackResult.error({
    required final Exception error,
    final Duration duration = Duration.zero,
  }) => AudioPlaybackResult(success: false, duration: duration, error: error);
  const AudioPlaybackResult({
    required this.success,
    required this.duration,
    this.filePath,
    this.error,
    this.metadata,
  });

  /// Si la reproducción fue exitosa
  final bool success;

  /// Duración del audio reproducido
  final Duration duration;

  /// Ruta del archivo temporal usado (si aplica)
  final String? filePath;

  /// Error si la reproducción falló
  final Exception? error;

  /// Metadatos adicionales del audio
  final Map<String, dynamic>? metadata;

  @override
  String toString() =>
      'AudioPlaybackResult(success: $success, duration: ${duration.inMilliseconds}ms)';
}
