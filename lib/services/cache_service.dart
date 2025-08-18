import 'dart:convert';
import 'dart:io';
import 'package:ai_chan/utils/log_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/cache_utils.dart';

class CacheService {
  static const String _audioSubDir = 'audio';
  static const String _voicesSubDir = 'voices';

  /// Obtiene el directorio de caché base
  static Future<Directory> getCacheDirectory() async {
    try {
      return await getLocalCacheDir();
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
      final cachedFile = File('${audioDir.path}/$hash.mp3');

      if (await cachedFile.exists()) {
        Log.d('[Cache] Audio encontrado en caché: ${cachedFile.path}');
        return cachedFile;
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
      final cachedFile = File('${audioDir.path}/$hash.mp3');

      await cachedFile.writeAsBytes(audioData);
      Log.d('[Cache] Audio guardado en caché: ${cachedFile.path}');
      return cachedFile;
    } catch (e) {
      Log.e('[Cache] Error guardando audio en caché: $e');
      return null;
    }
  }

  /// Guarda lista de voces en caché
  static Future<void> saveVoicesToCache({required List<Map<String, dynamic>> voices, required String provider}) async {
    try {
      final voicesDir = await getVoicesCacheDirectory();
      final cacheFile = File('${voicesDir.path}/${provider}_voices_cache.json');

      final cacheData = {'provider': provider, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'voices': voices};

      await cacheFile.writeAsString(jsonEncode(cacheData));
      Log.d('[Cache] Voces $provider guardadas en caché: ${voices.length} voces');
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
          debugPrint('[Cache] Caché de voces $provider expirado (${cacheAge ~/ (24 * 60 * 60 * 1000)} días)');
          return null;
        }
      }

      final cachedVoices = (cached['voices'] as List<dynamic>?) ?? [];
      debugPrint('[Cache] Voces $provider cargadas desde caché: ${cachedVoices.length} voces');

      return cachedVoices.map((v) => Map<String, dynamic>.from(v)).toList();
    } catch (e) {
      debugPrint('[Cache] Error leyendo voces desde caché: $e');
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
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
