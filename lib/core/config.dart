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

  /// Devuelve el DEFAULT_TEXT_MODEL y lanza si no está configurado.
  static String requireDefaultTextModel() {
    final v = getDefaultTextModel();
    if (v.trim().isEmpty) {
      throw Exception('DEFAULT_TEXT_MODEL no está configurado');
    }
    return v;
  }

  /// Devuelve el DEFAULT_IMAGE_MODEL y lanza si no está configurado.
  static String requireDefaultImageModel() {
    final v = getDefaultImageModel();
    if (v.trim().isEmpty) {
      throw Exception('DEFAULT_IMAGE_MODEL no está configurado');
    }
    return v;
  }

  static String getOpenAIKey() => _get('OPENAI_API_KEY', '');
  static String getGeminiKey() => _get('GEMINI_API_KEY', '');
  static String getOpenAIRealtimeModel() => _get('OPENAI_REALTIME_MODEL', '');

  /// Devuelve el OPENAI_REALTIME_MODEL y lanza si no está configurado.
  static String requireOpenAIRealtimeModel() {
    final v = getOpenAIRealtimeModel();
    if (v.trim().isEmpty) {
      throw Exception('OPENAI_REALTIME_MODEL no está configurado');
    }
    return v;
  }

  static String getAudioProvider() => _get('AUDIO_PROVIDER', 'gemini');
  static String getOpenaiVoice() => _get('OPENAI_VOICE_NAME', '');
  static String getGoogleVoice() => _get('GOOGLE_VOICE_NAME', '');

  static String getGoogleRealtimeModel() => _get('GOOGLE_REALTIME_MODEL', '');

  /// Devuelve el GOOGLE_REALTIME_MODEL y lanza si no está configurado.
  static String requireGoogleRealtimeModel() {
    final v = getGoogleRealtimeModel();
    if (v.trim().isEmpty) {
      throw Exception('GOOGLE_REALTIME_MODEL no está configurado');
    }
    return v;
  }

  static String _get(String key, String fallback) {
    try {
      if (_overrides != null && _overrides!.containsKey(key)) {
        return _overrides![key]!;
      }
      return dotenv.env[key] ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Acceso genérico para claves no previstas por getters específicos.
  static String get(String key, String fallback) => _get(key, fallback);

  /// Getter para el modo TTS (google/openai)
  static String getAudioTtsMode() => _get('AUDIO_TTS_MODE', 'google');

  /// Tamaño por defecto del bloque de resumen en MemorySummaryService
  static int getSummaryBlockSize() {
    final v = _get('SUMMARY_BLOCK_SIZE', '32');
    return int.tryParse(v) ?? 32;
  }

  /// Inicializa la configuración cargando `.env`.
  ///
  /// Si `dotenvContents` se proporciona, carga los valores desde la cadena
  /// (útil para tests). Devuelve cuando la carga ha terminado.
  static Future<void> initialize({String? dotenvContents}) async {
    if (dotenvContents != null) {
      // testLoad es sincrónico pero mantenemos la paridad con el helper de tests
      dotenv.testLoad(fileInput: dotenvContents);
      return;
    }
    try {
      await dotenv.load();
    } catch (_) {
      // Si no hay .env, no fallamos: se pueden usar overrides en tests
      const defaultContents = '''
DEFAULT_TEXT_MODEL=gemini-2.5-flash
DEFAULT_IMAGE_MODEL=gpt-4.1-mini
GOOGLE_REALTIME_MODEL=gemini-2.5-flash
APP_LOG_LEVEL=trace
SUMMARY_BLOCK_SIZE=32
''';
      dotenv.testLoad(fileInput: defaultContents);
    }
  }
}
