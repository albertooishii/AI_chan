import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/android_native_tts_service.dart';
import 'package:flutter/foundation.dart';

/// Adapter que implementa ICallTtsService usando AndroidNativeTtsService
class AndroidNativeTtsAdapter implements ICallTtsService {
  const AndroidNativeTtsAdapter();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      if (!await AndroidNativeTtsService.isNativeTtsAvailable()) {
        return [];
      }
      return await AndroidNativeTtsService.getAvailableVoices();
    } on Exception catch (e) {
      debugPrint('[AndroidNativeTtsAdapter] getAvailableVoices error: $e');
      return [];
    }
  }

  @override
  Future<String?> synthesizeToFile({required final String text, final Map<String, dynamic>? options}) async {
    try {
      if (!await AndroidNativeTtsService.isNativeTtsAvailable()) {
        return null;
      }

      final voice = options?['voice'] as String?;
      final speed = options?['speed'] as double? ?? 1.0;
      final pitch = options?['pitch'] as double? ?? 1.0;
      final outputPath = options?['outputPath'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}.wav';

      return await AndroidNativeTtsService.synthesizeToFile(
        text: text,
        outputPath: outputPath,
        voiceName: voice,
        speechRate: speed,
        pitch: pitch,
      );
    } on Exception catch (e) {
      debugPrint('[AndroidNativeTtsAdapter] synthesizeToFile error: $e');
      return null;
    }
  }

  // Implementación de ITtsAdapter
  @override
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    // AndroidNativeTtsService no soporta síntesis directa a bytes
    // Retornamos bytes vacíos para indicar que no es compatible
    return Uint8List(0);
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[AndroidNativeTtsAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    return await AndroidNativeTtsService.isNativeTtsAvailable();
  }
}
