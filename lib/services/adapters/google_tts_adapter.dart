import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/services/google_speech_service.dart';
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
  Future<String?> synthesizeToFile({required String text, Map<String, dynamic>? options}) async {
    try {
      final languageCode = options?['languageCode'] as String? ?? 'es-ES';
      final voice = options?['voice'] as String? ?? GoogleSpeechService.getVoiceConfig()['voiceName'];
      final file = await GoogleSpeechService.textToSpeechFile(text: text, voiceName: voice, languageCode: languageCode);
      return file?.path;
    } catch (e) {
      debugPrint('[GoogleTtsAdapter] synthesizeToFile error: $e');
      return null;
    }
  }
}
