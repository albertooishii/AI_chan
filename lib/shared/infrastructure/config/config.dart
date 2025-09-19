import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;
import 'package:ai_chan/shared.dart';

/// Helper centralizado para acceder a configuración derivada de .env.
/// Permite inyectar overrides en tests mediante `Config.setOverrides`.
/// Los modelos, voces y proveedores se configuran en assets/ai_providers_config.yaml
class Config {
  static Map<String, String>? _overrides;

  /// Inyecta valores para tests o entornos controlados.
  static void setOverrides(final Map<String, String>? overrides) {
    _overrides = overrides;
  }

  // --- Dynamic API Keys (Arrays) ---
  /// Parse JSON array from environment variable
  static List<String> parseApiKeysFromJson(final String envVar) {
    final jsonString = _get(envVar, '');
    if (jsonString.isEmpty) return [];

    try {
      final dynamic parsed = json.decode(jsonString);
      if (parsed is List) {
        return parsed
            .cast<String>()
            .where((final key) => key.isNotEmpty)
            .toList();
      }
    } on FormatException {
      // Fallback for legacy comma-separated format
      return jsonString
          .split(',')
          .map((final key) => key.trim())
          .where((final key) => key.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Get all API keys for OpenAI as a list
  static List<String> getOpenAIKeys() {
    return parseApiKeysFromJson('OPENAI_API_KEYS');
  }

  /// Get all API keys for Gemini as a list
  static List<String> getGeminiKeys() {
    return parseApiKeysFromJson('GEMINI_API_KEYS');
  }

  /// Get all API keys for Grok as a list
  static List<String> getGrokKeys() {
    return parseApiKeysFromJson('GROK_API_KEYS');
  }

  /// Get all API keys for Google Cloud as a list
  static List<String> getGoogleCloudKeys() {
    return parseApiKeysFromJson('GOOGLE_CLOUD_API_KEYS');
  }

  // --- Application Configuration ---
  static String getAppName() => _get('APP_NAME', 'AI-チャン');

  static int getSummaryBlockSize() {
    final v = _get('SUMMARY_BLOCK_SIZE', '32');
    return int.tryParse(v) ?? 32;
  }

  /// Acceso genérico para claves no previstas por getters específicos.
  static String get(final String key, final String fallback) =>
      _get(key, fallback);

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

  // --- Default Models (configured in assets/ai_providers_config.yaml) ---

  /// Modelo STT dinámico - obtenido del primer proveedor con capacidad de transcripción
  static String getSTTModel() {
    final manager = AIProviderManager.instance;

    // 🚀 DINÁMICO: Buscar el primer proveedor que soporte transcripción
    final providers = manager.getProvidersByCapability(
      AICapability.audioTranscription,
    );

    for (final providerId in providers) {
      final provider = manager.providers[providerId];
      if (provider != null &&
          provider.supportsCapability(AICapability.audioTranscription)) {
        final models =
            provider.metadata.availableModels[AICapability.audioTranscription];
        if (models != null && models.isNotEmpty) {
          // Buscar modelo transcribe específico o usar el primero disponible
          final transcribeModel = models.firstWhere(
            (final model) =>
                model.toLowerCase().contains('transcribe') ||
                model.toLowerCase().contains('whisper'),
            orElse: () => models.first,
          );
          return transcribeModel;
        }
      }
    }

    // Fallback dinámico
    return 'unknown-stt-model';
  }

  /// Modelo Realtime dinámico - obtenido del primer proveedor con capacidad realtime
  static String getOpenAIRealtimeModel() {
    final manager = AIProviderManager.instance;

    // 🚀 DINÁMICO: Buscar el primer proveedor que soporte conversación en tiempo real
    final providers = manager.getProvidersByCapability(
      AICapability.realtimeConversation,
    );

    for (final providerId in providers) {
      final provider = manager.providers[providerId];
      if (provider != null &&
          provider.supportsCapability(AICapability.realtimeConversation)) {
        final models = provider
            .metadata
            .availableModels[AICapability.realtimeConversation];
        if (models != null && models.isNotEmpty) {
          // Buscar modelo realtime específico o usar el primero disponible
          final realtimeModel = models.firstWhere(
            (final model) => model.toLowerCase().contains('realtime'),
            orElse: () => models.first,
          );
          return realtimeModel;
        }
      }
    }

    // Fallback dinámico
    return 'unknown-realtime-model';
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
      // Cargar dotenv desde el archivo .env en el directorio raíz del proyecto
      await dotenv.load();
      debugPrint('Config: dotenv loaded successfully from .env file');
    } on Exception catch (e) {
      debugPrint('Config: Failed to load .env file: $e');
      // Si no hay .env en disco, cargamos valores mínimos esenciales
      const defaultContents = '''
DEBUG_MODE=basic
SUMMARY_BLOCK_SIZE=32
AUDIO_TTS_MODE=google
PREFERRED_AUDIO_FORMAT=mp3
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
      debugPrint('Config: Loaded minimal default configuration manually');
    }
  }

  // Helper para escribir un archivo temporal con formato .env.
  static Future<File> _writeTempEnv(final String contents) async {
    final tmp = File('${Directory.systemTemp.path}/.env_ai_chan_tmp');
    await tmp.writeAsString(contents, flush: true);
    return tmp;
  }
}
