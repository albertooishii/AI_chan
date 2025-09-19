import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared.dart' as image_utils;
import 'package:ai_chan/shared.dart' as audio_utils;

/// Utilidades para la gestión de datos de la aplicación (limpieza, backup, etc.)
class AppDataUtils {
  /// Borra completamente todos los datos de la aplicación:
  /// - Preferencias compartidas
  /// - Archivos de imágenes
  /// - Archivos de audio
  /// - Archivos de backup locales
  ///
  /// Esta función es útil para el botón "Borrar todo (debug)" y para
  /// reset completo de la aplicación.
  static Future<void> clearAllAppData() async {
    Log.i(
      'AppDataUtils: iniciando limpieza completa de datos de la app',
      tag: 'APP_DATA',
    );

    // Limpiar preferencias compartidas
    await PrefsUtils.clearAll();
    Log.d('AppDataUtils: preferencias compartidas limpiadas', tag: 'APP_DATA');

    // Borrar todos los archivos de imágenes
    try {
      final imgDir = await image_utils.getLocalImageDir();
      if (imgDir.existsSync()) {
        await for (final entity in imgDir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
              Log.d(
                'AppDataUtils: imagen borrada: ${entity.path}',
                tag: 'APP_DATA',
              );
            } on Exception catch (e) {
              Log.w(
                'AppDataUtils: no se pudo borrar imagen ${entity.path}: $e',
                tag: 'APP_DATA',
              );
            }
          }
        }
      }
    } on Exception catch (e) {
      Log.e(
        'AppDataUtils: error limpiando directorio de imágenes',
        tag: 'APP_DATA',
        error: e,
      );
    }

    // Borrar todos los archivos de audio
    try {
      final audioDir = await audio_utils.getLocalAudioDir();
      if (audioDir.existsSync()) {
        await for (final entity in audioDir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
              Log.d(
                'AppDataUtils: audio borrado: ${entity.path}',
                tag: 'APP_DATA',
              );
            } on Exception catch (e) {
              Log.w(
                'AppDataUtils: no se pudo borrar audio ${entity.path}: $e',
                tag: 'APP_DATA',
              );
            }
          }
        }
      }
    } on Exception catch (e) {
      Log.e(
        'AppDataUtils: error limpiando directorio de audio',
        tag: 'APP_DATA',
        error: e,
      );
    }

    // Borrar archivos de backup locales en el directorio de documentos
    try {
      final docDir = await getApplicationDocumentsDirectory();
      await for (final entity in docDir.list()) {
        if (entity is File &&
            entity.path.contains('ai_chan_backup_') &&
            entity.path.endsWith('.zip')) {
          try {
            await entity.delete();
            Log.d(
              'AppDataUtils: backup borrado: ${entity.path}',
              tag: 'APP_DATA',
            );
          } on Exception catch (e) {
            Log.w(
              'AppDataUtils: no se pudo borrar backup ${entity.path}: $e',
              tag: 'APP_DATA',
            );
          }
        }
      }
    } on Exception catch (e) {
      Log.e(
        'AppDataUtils: error limpiando archivos de backup',
        tag: 'APP_DATA',
        error: e,
      );
    }

    Log.i(
      'AppDataUtils: limpieza completa de datos finalizada',
      tag: 'APP_DATA',
    );
  }

  /// Obtiene estadísticas de uso de espacio por tipo de archivo
  /// Útil para mostrar al usuario cuánto espacio está usando cada categoría
  static Future<Map<String, int>> getStorageUsageStats() async {
    final stats = <String, int>{'images': 0, 'audio': 0, 'backups': 0};

    try {
      // Calcular tamaño de imágenes
      final imgDir = await image_utils.getLocalImageDir();
      if (imgDir.existsSync()) {
        await for (final entity in imgDir.list()) {
          if (entity is File) {
            try {
              final size = await entity.length();
              stats['images'] = stats['images']! + size;
            } on Exception catch (_) {}
          }
        }
      }
    } on Exception catch (_) {}

    try {
      // Calcular tamaño de audio
      final audioDir = await audio_utils.getLocalAudioDir();
      if (audioDir.existsSync()) {
        await for (final entity in audioDir.list()) {
          if (entity is File) {
            try {
              final size = await entity.length();
              stats['audio'] = stats['audio']! + size;
            } on Exception catch (_) {}
          }
        }
      }
    } on Exception catch (_) {}

    try {
      // Calcular tamaño de backups
      final docDir = await getApplicationDocumentsDirectory();
      await for (final entity in docDir.list()) {
        if (entity is File &&
            entity.path.contains('ai_chan_backup_') &&
            entity.path.endsWith('.zip')) {
          try {
            final size = await entity.length();
            stats['backups'] = stats['backups']! + size;
          } on Exception catch (_) {}
        }
      }
    } on Exception catch (_) {}

    return stats;
  }

  /// Formatea bytes a una representación legible (KB, MB, GB, TB)
  static String formatBytes(final int bytes) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor().clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, i);

    String sizeStr;
    if (size >= 100 || size.truncateToDouble() == size) {
      sizeStr = size.toStringAsFixed(0);
    } else if (size >= 10) {
      sizeStr = size.toStringAsFixed(1);
    } else {
      sizeStr = size.toStringAsFixed(2);
    }

    return '$sizeStr ${suffixes[i]}';
  }
}
