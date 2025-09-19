import 'dart:convert';
import 'dart:io';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';
import 'package:ai_chan/shared/infrastructure/utils/app_data_utils.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/shared/infrastructure/utils/cache_utils.dart'
    as cache_utils;

class CacheService {
  static const String _audioSubDir = 'audio';
  static const String _voicesSubDir = 'voices';
  static const String _modelsSubDir = 'models';

  /// Obtiene el directorio de caché base
  static Future<Directory> getCacheDirectory() async {
    try {
      return await cache_utils.getLocalCacheDir();
    } on Exception catch (e) {
      Log.e('Error getting local cache directory: $e');
      // Fallback to application support directory
      return await getApplicationSupportDirectory();
    }
  }

  /// Obtiene el directorio de caché de audio
  static Future<Directory> getAudioCacheDirectory() async {
    final cacheDir = await getCacheDirectory();
    final audioDir = Directory('${cacheDir.path}/$_audioSubDir');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
    return audioDir;
  }

  /// Obtiene el directorio de caché de voces
  static Future<Directory> getVoicesCacheDirectory() async {
    final cacheDir = await getCacheDirectory();
    final voicesDir = Directory('${cacheDir.path}/$_voicesSubDir');
    if (!voicesDir.existsSync()) {
      voicesDir.createSync(recursive: true);
    }
    return voicesDir;
  }

  /// Genera un hash único para el texto y configuración TTS
  static String generateTtsHash({
    required final String text,
    required final String voice,
    required final String languageCode,
    final String? provider,
    final double speakingRate = 1.0,
    final double pitch = 0.0,
  }) {
    // 🚀 DINÁMICO: Obtener provider por defecto si no se especifica
    final effectiveProvider = provider ?? _getDefaultTtsProvider();
    final input =
        '$effectiveProvider:$voice:$languageCode:$speakingRate:$pitch:$text';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Obtiene archivo de audio cacheado
  static Future<File?> getCachedAudioFile({
    required final String text,
    required final String voice,
    required final String languageCode,
    final String? provider,
    final double speakingRate = 1.0,
    final double pitch = 0.0,
    final String? extension,
  }) async {
    try {
      final hash = generateTtsHash(
        text: text,
        voice: voice,
        languageCode: languageCode,
        provider: provider,
        speakingRate: speakingRate,
        pitch: pitch,
      );

      final audioDir = await getAudioCacheDirectory();
      final ext = (extension != null && extension.trim().isNotEmpty)
          ? extension.trim().replaceAll('.', '')
          : 'mp3';
      final cachedFile = File('${audioDir.path}/$hash.$ext');

      if (cachedFile.existsSync()) {
        try {
          final len = await cachedFile.length();
          if (len > 0) {
            Log.d(
              '[Cache] Audio encontrado en caché: ${cachedFile.path} (size=$len)',
            );
            return cachedFile;
          } else {
            // Remove zero-length files to avoid playback errors and treat as cache miss
            Log.d(
              '[Cache] Found zero-length cached audio, deleting: ${cachedFile.path}',
            );
            try {
              await cachedFile.delete();
            } on Exception catch (_) {}
          }
        } on Exception catch (e) {
          Log.e('[Cache] Error checking cached file length: $e');
          return null;
        }
      }
      // Si no se encuentra, intentar con la voz por defecto del proveedor
      // Esto permite reutilizar archivos de audio cacheados creados con la voz por defecto
      // cuando el usuario especifica una voz diferente o vacía
      final effectiveProvider = provider ?? _getDefaultTtsProvider();

      // 🚀 DINÁMICO: Intentar con voz por defecto del provider actual
      try {
        final defaultVoice =
            effectiveProvider ==
                AIProviderConfigLoader.getDefaultAudioProvider()
            ? AIProviderConfigLoader.getDefaultVoiceFromCurrentProvider()
            : null; // Solo buscar en provider actual para evitar hardcoding

        if (defaultVoice != null &&
            defaultVoice.isNotEmpty &&
            defaultVoice != voice) {
          final altHash = generateTtsHash(
            text: text,
            voice: defaultVoice,
            languageCode: languageCode,
            provider: effectiveProvider,
            speakingRate: speakingRate,
            pitch: pitch,
          );
          final altFile = File('${audioDir.path}/$altHash.$ext');
          if (altFile.existsSync()) {
            Log.d(
              '[Cache] Audio encontrado en caché (voz por defecto de $effectiveProvider): ${altFile.path}',
            );
            return altFile;
          }
        }
      } on Exception catch (e) {
        Log.w(
          '[Cache] Error buscando con voz por defecto de $effectiveProvider: $e',
        );
      }
    } on Exception catch (e) {
      Log.e('[Cache] Error obteniendo audio cacheado: $e');
    }
    return null;
  }

  /// Guarda archivo de audio en caché
  static Future<File?> saveAudioToCache({
    required final Uint8List audioData,
    required final String text,
    required final String voice,
    required final String languageCode,
    final String? provider,
    final double speakingRate = 1.0,
    final double pitch = 0.0,
    final String? extension,
  }) async {
    try {
      final hash = generateTtsHash(
        text: text,
        voice: voice,
        languageCode: languageCode,
        provider: provider,
        speakingRate: speakingRate,
        pitch: pitch,
      );

      final audioDir = await getAudioCacheDirectory();
      final ext = (extension != null && extension.trim().isNotEmpty)
          ? extension.trim().replaceAll('.', '')
          : 'mp3';
      final cachedFile = File('${audioDir.path}/$hash.$ext');

      await cachedFile.writeAsBytes(audioData);
      try {
        final len = await cachedFile.length();
        if (len > 0) {
          Log.d(
            '[Cache] Audio guardado en caché: ${cachedFile.path} (size=$len)',
          );
          return cachedFile;
        } else {
          Log.e(
            '[Cache] Audio saved but file is zero-length: ${cachedFile.path}',
          );
          try {
            await cachedFile.delete();
          } on Exception catch (_) {}
          return null;
        }
      } on Exception catch (e) {
        Log.e('[Cache] Error verifying cached file: $e');
        return null;
      }
    } on Exception catch (e) {
      Log.e('[Cache] Error guardando audio en caché: $e');
      return null;
    }
  }

  /// Guarda lista de voces en caché
  static Future<void> saveVoicesToCache({
    required final List<Map<String, dynamic>> voices,
    required final String provider,
  }) async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      final cacheData = {
        'provider': provider,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'voices': voices,
      };

      await cacheFile.writeAsString(jsonEncode(cacheData));
      Log.d(
        '[Cache] Voces $provider guardadas en caché: ${voices.length} voces',
      );
    } on Exception catch (e) {
      Log.e('[Cache] Error guardando voces en caché: $e');
    }
  }

  /// Obtiene lista de voces desde caché
  static Future<List<Map<String, dynamic>>?> getCachedVoices({
    required final String provider,
    final bool forceRefresh = false,
  }) async {
    if (forceRefresh) return null;

    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      if (!cacheFile.existsSync()) return null;

      final raw = await cacheFile.readAsString();
      final cached = jsonDecode(raw) as Map<String, dynamic>;

      // Validar que el cache no sea muy viejo (7 días)
      final timestamp = cached['timestamp'] as int?;
      if (timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        const maxAge = 7 * 24 * 60 * 60 * 1000; // 7 días en ms
        if (cacheAge > maxAge) {
          debugPrint(
            '[Cache] Caché de voces $provider expirado (${cacheAge ~/ (24 * 60 * 60 * 1000)} días)',
          );
          return null;
        }
      }

      final cachedVoices = (cached['voices'] as List<dynamic>?) ?? [];
      debugPrint(
        '[Cache] Voces $provider cargadas desde caché: ${cachedVoices.length} voces',
      );

      return cachedVoices
          .map((final v) => Map<String, dynamic>.from(v))
          .toList();
    } on Exception catch (e) {
      debugPrint('[Cache] Error leyendo voces desde caché: $e');
      return null;
    }
  }

  /// Guarda lista de modelos en caché
  static Future<void> saveModelsToCache({
    required final List<String> models,
    required final String provider,
  }) async {
    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);
      final cacheFile = File('${modelsDir.path}/${provider}_models_cache.json');

      final cacheData = {
        'provider': provider,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'models': models,
      };

      await cacheFile.writeAsString(jsonEncode(cacheData));
      Log.d(
        '[Cache] Modelos $provider guardados en caché: ${models.length} modelos',
      );
    } on Exception catch (e) {
      Log.e('[Cache] Error guardando modelos en caché: $e');
    }
  }

  /// Obtiene lista de modelos desde caché por proveedor
  static Future<List<String>?> getCachedModels({
    required final String provider,
    final bool forceRefresh = false,
  }) async {
    if (forceRefresh) return null;

    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      final cacheFile = File('${modelsDir.path}/${provider}_models_cache.json');

      if (!cacheFile.existsSync()) return null;

      final raw = await cacheFile.readAsString();
      final cached = jsonDecode(raw) as Map<String, dynamic>;

      // Validar que el cache no sea muy viejo (7 días)
      final timestamp = cached['timestamp'] as int?;
      if (timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        const maxAge = 7 * 24 * 60 * 60 * 1000; // 7 días en ms
        if (cacheAge > maxAge) {
          debugPrint(
            '[Cache] Caché de modelos $provider expirado (${cacheAge ~/ (24 * 60 * 60 * 1000)} días)',
          );
          return null;
        }
      }

      final cachedModels = (cached['models'] as List<dynamic>?) ?? [];
      debugPrint(
        '[Cache] Modelos $provider cargados desde caché: ${cachedModels.length} modelos',
      );

      return cachedModels.map((final m) => m.toString()).toList();
    } on Exception catch (e) {
      debugPrint('[Cache] Error leyendo modelos desde caché: $e');
      return null;
    }
  }

  /// Elimina caché de voces de un proveedor específico
  static Future<void> clearVoicesCache({required final String provider}) async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      if (cacheFile.existsSync()) {
        await cacheFile.delete();
        debugPrint('[Cache] Caché de voces $provider eliminado');
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error eliminando caché de voces $provider: $e');
    }
  }

  /// Elimina caché de modelos de un proveedor específico
  static Future<void> clearModelsCache({required final String provider}) async {
    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      final cacheFile = File('${modelsDir.path}/${provider}_models_cache.json');

      if (cacheFile.existsSync()) {
        await cacheFile.delete();
        debugPrint('[Cache] Caché de modelos $provider eliminado');
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error eliminando caché de modelos $provider: $e');
    }
  }

  /// Elimina todos los archivos de caché de voces (usado para forzar refresh completo)
  static Future<void> clearAllVoicesCache() async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      if (voicesDir.existsSync()) {
        final entities = voicesDir.listSync();
        for (final e in entities) {
          try {
            if (e is File) await e.delete();
            if (e is Directory) await e.delete(recursive: true);
          } on Exception catch (e) {
            debugPrint('[Cache] Warning clearing voice cache entry: $e');
          }
        }
        debugPrint('[Cache] All voices cache cleared');
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error clearing all voices cache: $e');
    }
  }

  /// Elimina todos los archivos de caché de modelos (usado para forzar refresh completo)
  static Future<void> clearAllModelsCache() async {
    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      if (modelsDir.existsSync()) {
        final entities = modelsDir.listSync();
        for (final e in entities) {
          try {
            if (e is File) await e.delete();
            if (e is Directory) await e.delete(recursive: true);
          } on Exception catch (e) {
            debugPrint('[Cache] Warning clearing models cache entry: $e');
          }
        }
        debugPrint('[Cache] All models cache cleared');
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error clearing all models cache: $e');
    }
  }

  /// Elimina todo el caché de audio
  static Future<void> clearAudioCache() async {
    try {
      final audioDir = await getAudioCacheDirectory();
      if (audioDir.existsSync()) {
        await audioDir.delete(recursive: true);
        debugPrint('[Cache] Caché de audio eliminado');
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error eliminando caché de audio: $e');
    }
  }

  /// Obtiene el tamaño total del caché en bytes
  static Future<int> getCacheSize() async {
    int totalSize = 0;
    try {
      final cacheDir = await getCacheDirectory();
      if (cacheDir.existsSync()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } on Exception catch (e) {
      debugPrint('[Cache] Error calculando tamaño de caché: $e');
    }
    return totalSize;
  }

  /// Formatea el tamaño en bytes a una cadena legible
  static String formatCacheSize(final int bytes) {
    return AppDataUtils.formatBytes(bytes);
  }

  /// 🚀 DINÁMICO: Obtener el proveedor TTS por defecto dinámicamente
  static String _getDefaultTtsProvider() {
    try {
      // Obtener el primer proveedor con capacidad TTS
      final providers = AIProviderManager.instance.getProvidersByCapability(
        AICapability.audioGeneration,
      );
      if (providers.isNotEmpty) {
        return providers.first;
      }
      // Fallback a los proveedores disponibles
      final allProviders = AIProviderManager.instance.providers.keys.toList();
      return allProviders.isNotEmpty ? allProviders.first : 'unknown';
    } on Exception catch (e) {
      Log.w('Error obteniendo proveedor TTS por defecto: $e');
      // Fallback ultimate
      return 'unknown';
    }
  }
}
