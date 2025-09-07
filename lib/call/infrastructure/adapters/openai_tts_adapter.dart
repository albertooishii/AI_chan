import 'dart:io';
import 'dart:typed_data';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/shared/services/openai_tts_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/call/infrastructure/services/openai_speech_service.dart';

/// Adapter para OpenAITtsService que implementa ICallTtsService
class OpenAITtsAdapter implements ICallTtsService {
  OpenAITtsAdapter(this._ttsService);
  final OpenAITtsService _ttsService;

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    try {
      // Usar OpenAITtsService para sintetizar
      final result = await _ttsService.synthesizeAndPlay(
        text,
        options: options,
      );

      if (result != null) {
        return result.audioPath;
      } else {
        Log.e('[OpenAITtsAdapter] Error: synthesizeAndPlay retornó null');
        return null;
      }
    } on Exception catch (e) {
      Log.e('[OpenAITtsAdapter] Error en synthesizeToFile: $e');
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
      // Crear archivo temporal para la síntesis
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/openai_tts_temp_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      final result = await synthesizeToFile(
        text: text,
        options: {
          'voice': voice != 'default' ? voice : 'alloy',
          'speed': speed,
        },
      );

      if (result != null && tempFile.existsSync()) {
        final bytes = await tempFile.readAsBytes();
        // Limpiar archivo temporal
        try {
          await tempFile.delete();
        } on Exception catch (e) {
          Log.w('[OpenAITtsAdapter] Error limpiando archivo temporal: $e');
        }
        return bytes;
      } else {
        throw Exception('No se pudo sintetizar el audio');
      }
    } on Exception catch (e) {
      Log.e('[OpenAITtsAdapter] Error en synthesize: $e');
      throw Exception('Error sintetizando audio: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      return await OpenAISpeechService.fetchOpenAIVoicesStatic();
    } on Exception catch (e) {
      Log.e('[OpenAITtsAdapter] Error obteniendo voces disponibles: $e');
      return [];
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      // Verificar si hay API key configurada
      final voices = await getAvailableVoices();
      return voices.isNotEmpty;
    } on Exception catch (e) {
      Log.e('[OpenAITtsAdapter] Error verificando disponibilidad: $e');
      return false;
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    Log.d('[OpenAITtsAdapter] Configuración aplicada: $config');
  }
}
