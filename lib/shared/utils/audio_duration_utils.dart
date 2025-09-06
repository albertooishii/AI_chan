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

      // Crear un AudioPlayer temporal para obtener la duración
      final player = ap.AudioPlayer();

      try {
        // Cargar el archivo
        await player.setSourceDeviceFile(filePath);

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
          return null;
        }
      } on Exception catch (e) {
        debugPrint(
          '🔍 [DEBUG][AudioDuration] Error getting duration for $filePath: $e',
        );
        await player.dispose();
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
