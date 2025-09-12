/// Enumeración para los diferentes modos de audio soportados
enum AudioMode {
  /// Modo híbrido: TTS + STT + modelo de texto
  /// Recomendado para: onboarding, chat, interacciones simples
  hybrid,

  /// Modo realtime: Conexión directa con provider realtime
  /// Recomendado para: llamadas de voz, conversaciones en tiempo real
  realtime,
}

/// Extensión para AudioMode con funcionalidades útiles
extension AudioModeExtension on AudioMode {
  /// Nombre legible del modo
  String get displayName {
    switch (this) {
      case AudioMode.hybrid:
        return 'Híbrido (TTS+STT)';
      case AudioMode.realtime:
        return 'Tiempo Real';
    }
  }

  /// Identificador para configuración YAML
  String get identifier {
    switch (this) {
      case AudioMode.hybrid:
        return 'hybrid';
      case AudioMode.realtime:
        return 'realtime';
    }
  }

  /// Descripción del modo
  String get description {
    switch (this) {
      case AudioMode.hybrid:
        return 'Combina TTS + STT + modelo de texto para simular conversación en tiempo real';
      case AudioMode.realtime:
        return 'Conexión directa con provider realtime para conversación nativa';
    }
  }

  /// Crear desde identificador
  static AudioMode? fromIdentifier(final String identifier) {
    switch (identifier.toLowerCase()) {
      case 'hybrid':
        return AudioMode.hybrid;
      case 'realtime':
        return AudioMode.realtime;
      default:
        return null;
    }
  }
}
