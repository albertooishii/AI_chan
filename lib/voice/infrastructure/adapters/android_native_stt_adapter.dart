import 'dart:async';
import 'dart:io';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Adapter que envuelve el plugin `speech_to_text` para ofrecer una
/// implementación de `ISttService` utilizando reconocimiento nativo
/// (on-device) cuando esté disponible.
class AndroidNativeSttAdapter implements ISttService {
  const AndroidNativeSttAdapter();

  /// Nota: `speech_to_text` está pensado para reconocimiento en vivo.
  /// Para transcribir archivos grabados intentamos abrir el archivo y
  /// ejecutar una sesión de reconocimiento en background reproduciéndolo
  /// hacia el recognizer es poco fiable. En este adapter preferimos usar
  /// el recognizer en modo `listen` si la plataforma soporta grabación
  /// en background. Como compromiso, si recibimos un archivo, intentamos
  /// devolver null para indicar que la app debe caer a OpenAI/Google.
  @override
  Future<String?> transcribeAudio(String path) async {
    try {
      if (!Platform.isAndroid) {
        Log.d('[AndroidSTT] Platform is not Android, skipping native STT');
        return null;
      }

      final file = File(path);
      if (!await file.exists()) {
        Log.d('[AndroidSTT] Audio file does not exist: $path');
        return null;
      }

      // speech_to_text package is primarily for live mic input. It does not
      // provide a reliable API to transcribe an arbitrary file. Rather than
      // implementing a fragile playback+listen approach here, return null so
      // callers can fallback to cloud-based transcription which is more
      // suitable for file transcription.
      Log.d(
        '[AndroidSTT] Received request to transcribe file with native STT, returning null to fallback (file transcription not supported)',
      );
      return null;
    } catch (e) {
      Log.e('[AndroidSTT] transcribeAudio error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({required String filePath, Map<String, dynamic>? options}) async {
    return await transcribeAudio(filePath);
  }
}
