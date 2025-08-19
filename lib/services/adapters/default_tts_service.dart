import 'dart:io';

import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/services/google_speech_service.dart';
import 'package:ai_chan/services/android_native_tts_service.dart';
import 'package:ai_chan/services/adapters/openai_adapter.dart';
// dotenv usage removed — use Config getters instead
// removed unused runtime/openai imports: use OpenAIAdapter wrapper instead
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default TTS service that tries native -> Google -> OpenAI in that order.
class DefaultTtsService implements ITtsService {
  const DefaultTtsService();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    // Merge available voices from Android native (if any) and Google TTS.
    final List<Map<String, dynamic>> voices = [];
    try {
      final native = await AndroidNativeTtsService.getAvailableVoices();
      voices.addAll(native);
    } catch (_) {}
    try {
      final google = await GoogleSpeechService.fetchGoogleVoices();
      voices.addAll(google.cast<Map<String, dynamic>>());
    } catch (_) {}
    return voices;
  }

  @override
  Future<String?> synthesizeToFile({required String text, Map<String, dynamic>? options}) async {
  final voice = options?['voice'] as String? ?? 'sage';
  final languageCode = options?['languageCode'] as String? ?? 'es-ES';

    // Resolve preferred provider from prefs/env (attempt to preserve previous behaviour)
    String provider = 'openai';
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_audio_provider');
      if (saved != null) {
        provider = (saved == 'gemini') ? 'google' : saved.toLowerCase();
      } else {
        final env = Config.getAudioProvider().toLowerCase();
        if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
      }
    } catch (_) {
      final env = Config.getAudioProvider().toLowerCase();
      if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
    }

    // 1) Try Android native TTS when available (mobile-first behaviour kept)
    try {
      if (AndroidNativeTtsService.isAndroid) {
        final isNativeAvailable = await AndroidNativeTtsService.isNativeTtsAvailable();
        if (isNativeAvailable) {
          try {
            final outputPath = '${Directory.systemTemp.path}/ai_chan_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
            final res = await AndroidNativeTtsService.synthesizeToFile(
              text: text,
              outputPath: outputPath,
              voiceName: voice,
              languageCode: languageCode,
            );
            if (res != null) return res;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2) Try Google TTS when configured or selected
    try {
      if (provider == 'google' && GoogleSpeechService.isConfigured) {
        final file = await GoogleSpeechService.textToSpeechFile(
          text: text,
          voiceName: voice,
          languageCode: languageCode,
        );
        if (file != null) return file.path;
      }
    } catch (_) {}

    // 3) Fallback to OpenAI adapter (default)
    try {
      final adapter = OpenAIAdapter(modelId: 'gpt-4o');
      final path = await adapter.textToSpeech(text, voice: voice);
      if (path != null) return path;
    } catch (_) {}

    return null;
  }
}
