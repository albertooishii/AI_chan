import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;

/// Helper centralizado para acceder a configuración derivada de .env.
/// Permite inyectar overrides en tests mediante `Config.setOverrides`.
class Config {
  static Map<String, String>? _overrides;

  /// Inyecta valores para tests o entornos controlados.
  static void setOverrides(Map<String, String>? overrides) {
    _overrides = overrides;
  }

  static String getDefaultTextModel() => _get('DEFAULT_TEXT_MODEL', '');
  static String getDefaultImageModel() => _get('DEFAULT_IMAGE_MODEL', '');
  static String getOpenAIKey() => _get('OPENAI_API_KEY', '');
  static String getGeminiKey() => _get('GEMINI_API_KEY', '');
  static String getAudioProvider() => _get('AUDIO_PROVIDER', 'gemini');
  static String getOpenaiVoice() => _get('OPENAI_VOICE', '');
  static String getGoogleLanguageCode() => _get('GOOGLE_LANGUAGE_CODE', 'es-ES');

  static String _get(String key, String fallback) {
    try {
      if (_overrides != null && _overrides!.containsKey(key)) return _overrides![key]!;
      return dotenv.env[key] ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
