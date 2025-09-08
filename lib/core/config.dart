import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;

/// Helper centralizado para acceder a configuración derivada de .env.
/// Permite inyectar overrides en tests mediante `Config.setOverrides`.
class Config {
  static Map<String, String>? _overrides;

  /// Inyecta valores para tests o entornos controlados.
  static void setOverrides(final Map<String, String>? overrides) {
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

  /// Modelo TTS para OpenAI (usado para síntesis de mensajes, no realtime calls).
  /// Valor por defecto alineado con la documentación: 'gpt-4o-mini-tts'.
  static String getOpenAITtsModel() =>
      _get('OPENAI_TTS_MODEL', 'gpt-4o-mini-tts');

  /// Modelo STT para OpenAI (usado en transcripción).
  /// Valor por defecto alineado con la documentación: 'gpt-4o-mini-transcribe'.
  static String getOpenAISttModel() =>
      _get('OPENAI_STT_MODEL', 'gpt-4o-mini-transcribe');

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
  static String getGrokKey() => _get('GROK_API_KEY', '');

  static String _get(final String key, final String fallback) {
    try {
      if (_overrides != null && _overrides!.containsKey(key)) {
        return _overrides![key]!;
      }
      return dotenv.env[key] ?? fallback;
    } on Exception catch (_) {
      return fallback;
    }
  }

  /// Nombre de la aplicación. Lee `APP_NAME` desde .env o devuelve el
  /// valor por defecto "AI-チャン'" si no está presente.
  static String getAppName() => _get('APP_NAME', 'AI-チャン');

  /// Acceso genérico para claves no previstas por getters específicos.
  static String get(final String key, final String fallback) =>
      _get(key, fallback);

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
  static Future<void> initialize({final String? dotenvContents}) async {
    // Si nos pasan contenido por parámetro (útil en tests), lo escribimos a un
    // archivo temporal y llamamos a dotenv.load(fileName: ...). Evitamos
    // invocar APIs removidas como `testLoad` y mantenemos compatibilidad con
    // la versión instalada de flutter_dotenv.
    if (dotenvContents != null) {
      final tmp = await _writeTempEnv(dotenvContents);
      try {
        await dotenv.load(fileName: tmp.path);
      } finally {
        try {
          await tmp.delete();
        } on Exception catch (_) {}
      }
      return;
    }

    try {
      // Inicializar dotenv primero
      await dotenv.load();
      debugPrint('Config: dotenv initialized successfully');

      // Intentar cargar el archivo .env manualmente
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final contents = await envFile.readAsString();
        final lines = contents.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final parts = trimmed.split('=');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join('=').trim();
            dotenv.env[key] = value;
          }
        }
        debugPrint('Config: Loaded .env file manually');
      } else {
        throw Exception('File not found');
      }
    } on Exception catch (e) {
      debugPrint('Config: Failed to load .env file: $e');
      // Si no hay .env en disco, cargamos valores por defecto
      const defaultContents = '''
DEFAULT_TEXT_MODEL=gemini-2.5-flash
DEFAULT_IMAGE_MODEL=gpt-4.1-mini
GOOGLE_REALTIME_MODEL=gemini-2.5-flash
DEBUG_MODE=full
SUMMARY_BLOCK_SIZE=32
''';
      final lines = defaultContents.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          dotenv.env[key] = value;
        }
      }
      debugPrint('Config: Loaded default configuration manually');
    }
  }

  // Helper para escribir un archivo temporal con formato .env.
  static Future<File> _writeTempEnv(final String contents) async {
    final tmp = File('${Directory.systemTemp.path}/.env_ai_chan_tmp');
    await tmp.writeAsString(contents, flush: true);
    return tmp;
  }
}
