/// Proveedores de servicios de voz disponibles
enum VoiceProvider { openai, google, gemini }

/// Extensión para VoiceProvider
extension VoiceProviderExtension on VoiceProvider {
  String get name {
    switch (this) {
      case VoiceProvider.openai:
        return 'openai';
      case VoiceProvider.google:
        return 'google';
      case VoiceProvider.gemini:
        return 'gemini';
    }
  }

  /// Determina si el proveedor soporta audio en tiempo real
  bool get supportsRealtime {
    switch (this) {
      case VoiceProvider.openai:
        return true;
      case VoiceProvider.google:
        return false; // Emulado vía STT/TTS
      case VoiceProvider.gemini:
        return false; // Emulado vía STT/TTS
    }
  }

  /// Determina si el proveedor requiere STT/TTS separados
  bool get requiresSeparateSTTTTS {
    switch (this) {
      case VoiceProvider.openai:
        return false;
      case VoiceProvider.google:
        return true;
      case VoiceProvider.gemini:
        return true;
    }
  }

  static VoiceProvider fromString(String value) {
    switch (value.toLowerCase()) {
      case 'openai':
        return VoiceProvider.openai;
      case 'google':
        return VoiceProvider.google;
      case 'gemini':
        return VoiceProvider.gemini;
      default:
        return VoiceProvider.gemini; // Default fallback
    }
  }
}

/// Helper para manejar VoiceProvider
class VoiceProviderHelper {
  /// Obtiene el proveedor por defecto desde configuración
  static VoiceProvider getDefaultProvider() {
    // This would typically read from configuration
    return VoiceProvider.gemini;
  }

  /// Lista de todos los proveedores disponibles
  static List<VoiceProvider> get allProviders => VoiceProvider.values;

  /// Lista de proveedores que soportan tiempo real nativo
  static List<VoiceProvider> get realtimeProviders =>
      VoiceProvider.values.where((p) => p.supportsRealtime).toList();

  /// Lista de proveedores que requieren STT/TTS separados
  static List<VoiceProvider> get sttTtsProviders =>
      VoiceProvider.values.where((p) => p.requiresSeparateSTTTTS).toList();
}
