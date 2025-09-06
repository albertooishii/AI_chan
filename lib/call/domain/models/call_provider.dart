/// Proveedores de servicios de voz disponibles
enum CallProvider { openai, google, gemini }

/// Extensión para CallProvider
extension CallProviderExtension on CallProvider {
  String get name {
    switch (this) {
      case CallProvider.openai:
        return 'openai';
      case CallProvider.google:
        return 'google';
      case CallProvider.gemini:
        return 'gemini';
    }
  }

  /// Determina si el proveedor soporta audio en tiempo real
  bool get supportsRealtime {
    switch (this) {
      case CallProvider.openai:
        return true;
      case CallProvider.google:
        return false; // Emulado vía STT/TTS
      case CallProvider.gemini:
        return false; // Emulado vía STT/TTS
    }
  }

  /// Determina si el proveedor requiere STT/TTS separados
  bool get requiresSeparateSTTTTS {
    switch (this) {
      case CallProvider.openai:
        return false;
      case CallProvider.google:
        return true;
      case CallProvider.gemini:
        return true;
    }
  }

  static CallProvider fromString(final String value) {
    switch (value.toLowerCase()) {
      case 'openai':
        return CallProvider.openai;
      case 'google':
        return CallProvider.google;
      case 'gemini':
        return CallProvider.gemini;
      default:
        return CallProvider.gemini; // Default fallback
    }
  }
}

/// Helper para manejar CallProvider
class CallProviderHelper {
  /// Obtiene el proveedor por defecto desde configuración
  static CallProvider getDefaultProvider() {
    // This would typically read from configuration
    return CallProvider.gemini;
  }

  /// Lista de todos los proveedores disponibles
  static List<CallProvider> get allProviders => CallProvider.values;

  /// Lista de proveedores que soportan tiempo real nativo
  static List<CallProvider> get realtimeProviders =>
      CallProvider.values.where((final p) => p.supportsRealtime).toList();

  /// Lista de proveedores que requieren STT/TTS separados
  static List<CallProvider> get sttTtsProviders =>
      CallProvider.values.where((final p) => p.requiresSeparateSTTTTS).toList();
}
