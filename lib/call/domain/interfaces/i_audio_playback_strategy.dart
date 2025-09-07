/// Interfaz para estrategias de reproducción de audio
abstract interface class IAudioPlaybackStrategy {
  /// Programa la reproducción de audio con timing específico
  void schedulePlayback(final Function playbackFunction);
}

/// Interfaz para la factory de estrategias de reproducción
abstract interface class IAudioPlaybackStrategyFactory {
  /// Crea una estrategia según el proveedor de AI
  IAudioPlaybackStrategy createStrategy(final String aiProvider);

  /// Obtiene la estrategia por defecto
  IAudioPlaybackStrategy getDefaultStrategy();

  /// Registra una nueva estrategia
  void registerStrategy(final String provider, final IAudioPlaybackStrategy strategy);
}
