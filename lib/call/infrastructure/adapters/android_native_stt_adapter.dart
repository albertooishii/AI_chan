import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Adapter que envuelve el plugin `speech_to_text` para ofrecer una
/// implementación de `ICallSttService` utilizando reconocimiento nativo
/// (on-device) cuando esté disponible.
class AndroidNativeSttAdapter implements ICallSttService {
  const AndroidNativeSttAdapter();

  /// Nota: `speech_to_text` está pensado para reconocimiento en vivo.
  /// Para transcribir archivos grabados intentamos abrir el archivo y
  /// ejecutar una sesión de reconocimiento en background reproduciéndolo
  /// hacia el recognizer es poco fiable. En este adapter preferimos usar
  /// el recognizer en modo `listen` si la plataforma soporta grabación
  /// en background. Como compromiso, si recibimos un archivo, intentamos
  /// devolver null para indicar que la app debe caer a OpenAI/Google.
  @override
  Future<String?> transcribeAudio(final String path) async {
    try {
      if (!Platform.isAndroid) {
        Log.d('[AndroidSTT] Platform is not Android, skipping native STT');
        return null;
      }

      final file = File(path);
      if (!file.existsSync()) {
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
    } on Exception catch (e) {
      Log.e('[AndroidSTT] transcribeAudio error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({required final String filePath, final Map<String, dynamic>? options}) async {
    return await transcribeAudio(filePath);
  }

  // Implementación de ISttAdapter
  @override
  Future<String> processAudio(final Uint8List audioData) async {
    try {
      // Para reconocimiento nativo, crear archivo temporal
      final tempFile = File('${Directory.systemTemp.path}/temp_native_audio.wav');
      await tempFile.writeAsBytes(audioData);
      final result = await transcribeAudio(tempFile.path);
      await tempFile.delete();
      return result ?? '';
    } on Exception catch (e) {
      Log.e('[AndroidNativeSttAdapter] processAudio error: $e');
      return '';
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    Log.d('[AndroidNativeSttAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    // Verificar si el reconocimiento nativo está disponible en la plataforma
    try {
      return Platform.isAndroid; // Simplificado por ahora
    } on Exception catch (_) {
      return false;
    }
  }
}
