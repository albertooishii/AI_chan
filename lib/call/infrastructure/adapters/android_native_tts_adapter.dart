import 'dart:io';
import 'dart:typed_data';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/android_native_tts_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Adapter que implementa ICallTtsService usando AndroidNativeTtsService
class AndroidNativeTtsAdapter implements ICallTtsService {
  const AndroidNativeTtsAdapter();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      if (!await AndroidNativeTtsService.isNativeTtsAvailableStatic()) {
        return [];
      }
      return await AndroidNativeTtsService.getAvailableVoicesStatic();
    } on Exception catch (e) {
      Log.e('[AndroidNativeTtsAdapter] Error obteniendo voces disponibles: $e');
      return [];
    }
  }

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    try {
      if (!await AndroidNativeTtsService.isNativeTtsAvailableStatic()) {
        return null;
      }

      final voice = options?['voice'] as String?;
      final speed = options?['speed'] as double? ?? 1.0;
      final pitch = options?['pitch'] as double? ?? 1.0;
      final outputPath =
          options?['outputPath'] as String? ??
          '${DateTime.now().millisecondsSinceEpoch}.wav';

      return await AndroidNativeTtsService.synthesizeToFileStatic(
        text: text,
        outputPath: outputPath,
        voiceName: voice,
        speechRate: speed,
        pitch: pitch,
      );
    } on Exception catch (e) {
      Log.e('[AndroidNativeTtsAdapter] Error en synthesizeToFile: $e');
      return null;
    }
  }

  @override
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    try {
      if (!await AndroidNativeTtsService.isNativeTtsAvailableStatic()) {
        throw Exception('Android Native TTS no está disponible');
      }

      // Crear archivo temporal para la síntesis
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/android_tts_temp_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      final result = await synthesizeToFile(
        text: text,
        options: {
          'voice': voice != 'default' ? voice : null,
          'speed': speed,
          'outputPath': tempFile.path,
        },
      );

      if (result != null && tempFile.existsSync()) {
        final bytes = await tempFile.readAsBytes();
        // Limpiar archivo temporal
        try {
          await tempFile.delete();
        } on Exception catch (e) {
          Log.w(
            '[AndroidNativeTtsAdapter] Error limpiando archivo temporal: $e',
          );
        }
        return bytes;
      } else {
        throw Exception('No se pudo sintetizar el audio');
      }
    } on Exception catch (e) {
      Log.e('[AndroidNativeTtsAdapter] Error en synthesize: $e');
      throw Exception('Error sintetizando audio: $e');
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    Log.d('[AndroidNativeTtsAdapter] Configuración aplicada: $config');
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await AndroidNativeTtsService.isNativeTtsAvailableStatic();
    } on Exception catch (e) {
      Log.e('[AndroidNativeTtsAdapter] Error verificando disponibilidad: $e');
      return false;
    }
  }
}
