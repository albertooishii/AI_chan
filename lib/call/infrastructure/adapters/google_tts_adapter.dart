import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_speech_service.dart';
import 'package:flutter/foundation.dart';

class GoogleTtsAdapter implements ITtsService {
  const GoogleTtsAdapter();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      return await GoogleSpeechService.fetchGoogleVoices();
    } catch (e) {
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
          GoogleSpeechService.getVoiceConfig()['voiceName'];
      final audioEncoding = options?['audioEncoding'] as String? ?? 'MP3';
      final sampleRateHertz = options?['sampleRateHertz'] as int? ?? 24000;
      var noCache = options?['noCache'] as bool? ?? false;
      // If the caller requests LINEAR16 / wav, avoid caching by default for realtime
      final fmt = (options?['format'] as String?) ?? audioEncoding;
      if (audioEncoding.toLowerCase().contains('linear16') ||
          fmt.toString().toLowerCase().contains('wav')) {
        noCache = true;
      }

      final file = await GoogleSpeechService.textToSpeechFile(
        text: text,
        voiceName: voice,
        languageCode: languageCode,
        audioEncoding: audioEncoding,
        sampleRateHertz: sampleRateHertz,
        noCache: noCache,
      );
      return file?.path;
    } catch (e) {
      debugPrint('[GoogleTtsAdapter] synthesizeToFile error: $e');
      return null;
    }
  }
}
