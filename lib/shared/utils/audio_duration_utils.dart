import 'dart:io';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

class AudioDurationUtils {
  /// Obtiene la duración real de un archivo de audio
  /// Devuelve null si no se puede obtener la duración
  static Future<Duration?> getAudioDuration(final String filePath) async {
    if (filePath.isEmpty) return null;

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('🔍 [DEBUG][AudioDuration] File does not exist: $filePath');
        return null;
      }

      // Verificar el tamaño del archivo
      final fileSize = file.lengthSync();
      debugPrint(
        '🔍 [DEBUG][AudioDuration] File size: $fileSize bytes for $filePath',
      );

      if (fileSize == 0) {
        debugPrint('🔍 [DEBUG][AudioDuration] File is empty: $filePath');
        return null;
      }

      // Crear un AudioPlayer temporal para obtener la duración
      final player = ap.AudioPlayer();

      try {
        // Cargar el archivo
        await player.setSourceDeviceFile(filePath);

        // Esperar más tiempo para que el player procese el archivo en desktop
        await Future.delayed(const Duration(milliseconds: 500));

        // Obtener la duración directamente desde el player
        final duration = await player.getDuration();

        await player.dispose();

        if (duration != null && duration.inMilliseconds > 0) {
          debugPrint(
            '🔍 [DEBUG][AudioDuration] Got duration for $filePath: ${duration.inMilliseconds}ms',
          );
          return duration;
        } else {
          debugPrint(
            '🔍 [DEBUG][AudioDuration] Duration is null or zero for: $filePath',
          );
          // Como fallback, estimar duración basada en el tamaño del archivo
          // Para MP3 de TTS: aproximadamente 16KB por segundo (128 kbps típico)
          // OpenAI TTS genera audio de alta calidad, generalmente 128kbps o más
          final estimatedSeconds = (fileSize / (16 * 1024)).round();
          if (estimatedSeconds > 0) {
            debugPrint(
              '🔍 [DEBUG][AudioDuration] Using estimated duration: ${estimatedSeconds}s based on file size (MP3 128kbps)',
            );
            return Duration(seconds: estimatedSeconds);
          }
          return null;
        }
      } on Exception catch (e) {
        debugPrint(
          '🔍 [DEBUG][AudioDuration] Error getting duration for $filePath: $e',
        );
        await player.dispose();

        // Como fallback, estimar duración basada en el tamaño del archivo
        // Para MP3 de TTS: aproximadamente 16KB por segundo (128 kbps típico)
        final estimatedSeconds = (fileSize / (16 * 1024)).round();
        if (estimatedSeconds > 0) {
          debugPrint(
            '🔍 [DEBUG][AudioDuration] Using estimated fallback duration: ${estimatedSeconds}s (MP3 128kbps)',
          );
          return Duration(seconds: estimatedSeconds);
        }
        return null;
      }
    } on Exception catch (e) {
      debugPrint(
        '🔍 [DEBUG][AudioDuration] Exception getting audio duration: $e',
      );
      return null;
    }
  }
}
