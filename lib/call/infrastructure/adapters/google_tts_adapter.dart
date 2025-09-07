import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';
import 'package:flutter/foundation.dart';

class GoogleTtsAdapter implements ICallTtsService {
  const GoogleTtsAdapter();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      return await GoogleSpeechService.fetchGoogleVoicesStatic();
    } on Exception catch (e) {
      debugPrint('[GoogleTtsAdapter] getAvailableVoices error: $e');
      return [];
    }
  }

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    try {
      final languageCode = options?['languageCode'] as String? ?? 'es-ES';
      final voice =
          options?['voice'] as String? ??
          GoogleSpeechService.getVoiceConfigStatic()['voiceName'];
      final audioEncoding = options?['audioEncoding'] as String? ?? 'MP3';
      final sampleRateHertz = options?['sampleRateHertz'] as int? ?? 24000;
      var noCache = options?['noCache'] as bool? ?? false;
      // If the caller requests LINEAR16 / wav, avoid caching by default for realtime
      final fmt = (options?['format'] as String?) ?? audioEncoding;
      if (audioEncoding.toLowerCase().contains('linear16') ||
          fmt.toString().toLowerCase().contains('wav')) {
        noCache = true;
      }

      final file = await GoogleSpeechService.textToSpeechFileStatic(
        text: text,
        voiceName: voice,
        languageCode: languageCode,
        audioEncoding: audioEncoding,
        sampleRateHertz: sampleRateHertz,
        noCache: noCache,
      );
      return file?.path;
    } on Exception catch (e) {
      debugPrint('[GoogleTtsAdapter] synthesizeToFile error: $e');
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
    try {
      final result = await GoogleSpeechService.textToSpeechStatic(
        text: text,
        voiceName: voice == 'default' ? 'es-ES-Wavenet-F' : voice,
        speakingRate: speed,
      );
      return result ?? Uint8List(0);
    } on Exception catch (e) {
      debugPrint('[GoogleTtsAdapter] synthesize error: $e');
      return Uint8List(0);
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[GoogleTtsAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    return GoogleSpeechService.isConfiguredStatic;
  }
}
