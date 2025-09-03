import 'dart:convert';
import 'dart:io';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../shared/utils/cache_utils.dart' as cache_utils;

class CacheService {
  static const String _audioSubDir = 'audio';
  static const String _voicesSubDir = 'voices';
  static const String _modelsSubDir = 'models';

  /// Obtiene el directorio de caché base
  static Future<Directory> getCacheDirectory() async {
    try {
      return await cache_utils.getLocalCacheDir();
    } catch (e) {
      Log.e('Error getting local cache directory: $e');
      // Fallback to application support directory
      return await getApplicationSupportDirectory();
    }
  }

  /// Obtiene el directorio de caché de audio
  static Future<Directory> getAudioCacheDirectory() async {
    final cacheDir = await getCacheDirectory();
    final audioDir = Directory('${cacheDir.path}/$_audioSubDir');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  /// Obtiene el directorio de caché de voces
  static Future<Directory> getVoicesCacheDirectory() async {
    final cacheDir = await getCacheDirectory();
    final voicesDir = Directory('${cacheDir.path}/$_voicesSubDir');
    if (!await voicesDir.exists()) {
      await voicesDir.create(recursive: true);
    }
    return voicesDir;
  }

  /// Genera un hash único para el texto y configuración TTS
  static String generateTtsHash({
    required String text,
    required String voice,
    required String languageCode,
    String provider = 'google',
    double speakingRate = 1.0,
    double pitch = 0.0,
  }) {
    final input = '$provider:$voice:$languageCode:$speakingRate:$pitch:$text';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Obtiene archivo de audio cacheado
  static Future<File?> getCachedAudioFile({
    required String text,
    required String voice,
    required String languageCode,
    String provider = 'google',
    double speakingRate = 1.0,
    double pitch = 0.0,
    String? extension,
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

      if (await cachedFile.exists()) {
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
            } catch (_) {}
          }
        } catch (e) {
          Log.e('[Cache] Error checking cached file length: $e');
          return null;
        }
      }
      // If not found and provider is Google, try the configured Google default
      // voice as an alias. This helps reuse previously cached files created
      // under the Google default voice when callers passed an OpenAI alias
      // or empty voice string.
      if (provider.toLowerCase() == 'google') {
        try {
          final googleDefault = Config.getGoogleVoice();
          if (googleDefault.isNotEmpty && googleDefault != voice) {
            final altHash = generateTtsHash(
              text: text,
              voice: googleDefault,
              languageCode: languageCode,
              provider: provider,
              speakingRate: speakingRate,
              pitch: pitch,
            );
            final altFile = File('${audioDir.path}/$altHash.$ext');
            if (await altFile.exists()) {
              Log.d(
                '[Cache] Audio encontrado en caché (alias Google default): ${altFile.path}',
              );
              return altFile;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      Log.e('[Cache] Error obteniendo audio cacheado: $e');
    }
    return null;
  }

  /// Guarda archivo de audio en caché
  static Future<File?> saveAudioToCache({
    required Uint8List audioData,
    required String text,
    required String voice,
    required String languageCode,
    String provider = 'google',
    double speakingRate = 1.0,
    double pitch = 0.0,
    String? extension,
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
          } catch (_) {}
          return null;
        }
      } catch (e) {
        Log.e('[Cache] Error verifying cached file: $e');
        return null;
      }
    } catch (e) {
      Log.e('[Cache] Error guardando audio en caché: $e');
      return null;
    }
  }

  /// Guarda lista de voces en caché
  static Future<void> saveVoicesToCache({
    required List<Map<String, dynamic>> voices,
    required String provider,
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
    } catch (e) {
      Log.e('[Cache] Error guardando voces en caché: $e');
    }
  }

  /// Obtiene lista de voces desde caché
  static Future<List<Map<String, dynamic>>?> getCachedVoices({
    required String provider,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) return null;

    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      if (!await cacheFile.exists()) return null;

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

      return cachedVoices.map((v) => Map<String, dynamic>.from(v)).toList();
    } catch (e) {
      debugPrint('[Cache] Error leyendo voces desde caché: $e');
      return null;
    }
  }

  /// Guarda lista de modelos en caché
  static Future<void> saveModelsToCache({
    required List<String> models,
    required String provider,
  }) async {
    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
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
    } catch (e) {
      Log.e('[Cache] Error guardando modelos en caché: $e');
    }
  }

  /// Obtiene lista de modelos desde caché por proveedor
  static Future<List<String>?> getCachedModels({
    required String provider,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) return null;

    try {
      final cacheDir = await getCacheDirectory();
      final modelsDir = Directory('${cacheDir.path}/$_modelsSubDir');
      final cacheFile = File('${modelsDir.path}/${provider}_models_cache.json');

      if (!await cacheFile.exists()) return null;

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

      return cachedModels.map((m) => m.toString()).toList();
    } catch (e) {
      debugPrint('[Cache] Error leyendo modelos desde caché: $e');
      return null;
    }
  }

  /// Elimina caché de voces de un proveedor específico
  static Future<void> clearVoicesCache({required String provider}) async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      if (await cacheFile.exists()) {
        await cacheFile.delete();
        debugPrint('[Cache] Caché de voces $provider eliminado');
      }
    } catch (e) {
      debugPrint('[Cache] Error eliminando caché de voces $provider: $e');
    }
  }

  /// Elimina todos los archivos de caché de voces (usado para forzar refresh completo)
  static Future<void> clearAllVoicesCache() async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      if (await voicesDir.exists()) {
        final entities = voicesDir.listSync();
        for (final e in entities) {
          try {
            if (e is File) await e.delete();
            if (e is Directory) await e.delete(recursive: true);
          } catch (e) {
            debugPrint('[Cache] Warning clearing voice cache entry: $e');
          }
        }
        debugPrint('[Cache] All voices cache cleared');
      }
    } catch (e) {
      debugPrint('[Cache] Error clearing all voices cache: $e');
    }
  }

  /// Elimina todo el caché de audio
  static Future<void> clearAudioCache() async {
    try {
      final audioDir = await getAudioCacheDirectory();
      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
        debugPrint('[Cache] Caché de audio eliminado');
      }
    } catch (e) {
      debugPrint('[Cache] Error eliminando caché de audio: $e');
    }
  }

  /// Obtiene el tamaño total del caché en bytes
  static Future<int> getCacheSize() async {
    int totalSize = 0;
    try {
      final cacheDir = await getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('[Cache] Error calculando tamaño de caché: $e');
    }
    return totalSize;
  }

  /// Formatea el tamaño en bytes a una cadena legible
  static String formatCacheSize(int bytes) {
    return AppDataUtils.formatBytes(bytes);
  }
}
