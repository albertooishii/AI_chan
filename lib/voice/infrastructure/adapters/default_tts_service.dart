import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/shared/services/google_speech_service.dart';
import 'package:ai_chan/shared/services/android_native_tts_service.dart';
import 'package:ai_chan/core/infrastructure/adapters/openai_adapter.dart';
import 'package:ai_chan/core/infrastructure/adapters/gemini_adapter.dart';
// dotenv usage removed — use Config getters instead
// removed unused runtime/openai imports: use OpenAIAdapter wrapper instead
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;

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

    debugPrint('[DefaultTTS] synthesizeToFile called - voice: $voice, languageCode: $languageCode');

    // Detectar automáticamente el proveedor basado en la voz seleccionada
    String provider = 'openai';

    // Lista de voces de OpenAI - si la voz está en esta lista, usar OpenAI
    const openAIVoices = ['sage', 'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];

    if (openAIVoices.contains(voice)) {
      provider = 'openai';
      debugPrint('[DefaultTTS] Auto-detected OpenAI voice: $voice, forcing OpenAI provider');
    } else {
      // Resolve preferred provider from prefs/env (attempt to preserve previous behaviour)
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
    }

    debugPrint('[DefaultTTS] Using provider: $provider for voice: $voice');

    // 1) Try Android native TTS when available (mobile-first behaviour kept) - ONLY for non-OpenAI and non-Google Cloud voices
    if (provider != 'openai' && provider != 'google') {
      debugPrint('[DefaultTTS] Trying Android native TTS for non-OpenAI/non-Google voice: $voice');
      try {
        if (AndroidNativeTtsService.isAndroid) {
          final isNativeAvailable = await AndroidNativeTtsService.isNativeTtsAvailable();
          if (isNativeAvailable) {
            try {
              final outputPath =
                  '${Directory.systemTemp.path}/ai_chan_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
              final res = await AndroidNativeTtsService.synthesizeToFile(
                text: text,
                outputPath: outputPath,
                voiceName: voice,
                languageCode: languageCode,
              );
              if (res != null) {
                debugPrint('[DefaultTTS] Android native TTS success: $res');
                return res;
              }
            } catch (e) {
              debugPrint('[DefaultTTS] Android native TTS error: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[DefaultTTS] Android native TTS exception: $e');
      }
    } else if (provider == 'openai') {
      debugPrint('[DefaultTTS] Skipping Android native TTS for OpenAI voice: $voice');
    } else if (provider == 'google') {
      debugPrint('[DefaultTTS] Skipping Android native TTS for Google Cloud voice: $voice');
    }

    // 2) Try Google TTS when configured or selected
    if (provider == 'google') {
      debugPrint('[DefaultTTS] Trying Google TTS for voice: $voice');
      try {
        if (GoogleSpeechService.isConfigured) {
          final file = await GoogleSpeechService.textToSpeechFile(
            text: text,
            voiceName: voice,
            languageCode: languageCode,
          );
          if (file != null) {
            debugPrint('[DefaultTTS] Google TTS success: ${file.path}');
            return file.path;
          }
          debugPrint('[DefaultTTS] Google TTS returned null');
        } else {
          debugPrint('[DefaultTTS] Google TTS not configured');
        }
      } catch (e) {
        debugPrint('[DefaultTTS] Google TTS error: $e');
      }
    }

    // 2.5) Direct OpenAI handling for OpenAI voices
    if (provider == 'openai') {
      debugPrint('[DefaultTTS] Trying direct OpenAI handling for voice: $voice');
      try {
        // Use OpenAI adapter directly with gpt model
        final runtime = runtime_factory.getRuntimeAIServiceForModel('gpt-4o-mini');
        final adapter = OpenAIAdapter(modelId: 'gpt-4o-mini', runtime: runtime);
        final path = await adapter.textToSpeech(text, voice: voice);
        if (path != null) {
          debugPrint('[DefaultTTS] Direct OpenAI success: $path');
          return path;
        } else {
          debugPrint('[DefaultTTS] Direct OpenAI returned null');
        }
      } catch (e) {
        debugPrint('[DefaultTTS] Direct OpenAI error: $e');
      }
    }

    // 3) Fallback to a runtime adapter using centralized runtime factory.
    // Project-wide default is Gemini ('gemini-2.5-flash'). If the chosen provider is OpenAI,
    // we prefer 'gpt-5-mini'. Otherwise use DEFAULT_TEXT_MODEL when configured.
    try {
      final defaultModel = Config.getDefaultTextModel();
      String modelToUse = defaultModel.isNotEmpty
          ? defaultModel
          : (provider == 'openai'
                ? (Config.getDefaultTextModel().isNotEmpty ? Config.getDefaultTextModel() : 'gpt-5-mini')
                : (Config.getDefaultTextModel().isNotEmpty ? Config.getDefaultTextModel() : 'gemini-2.5-flash'));

      debugPrint(
        '[DefaultTTS] Fallback to runtime adapter - provider: $provider, voice: $voice, modelToUse: $modelToUse',
      );

      final runtime = runtime_factory.getRuntimeAIServiceForModel(modelToUse);
      // Choose adapter wrapper according to model prefix
      if (modelToUse.startsWith('gpt-')) {
        debugPrint('[DefaultTTS] Using OpenAIAdapter for model: $modelToUse');
        final adapter = OpenAIAdapter(modelId: modelToUse, runtime: runtime);
        final path = await adapter.textToSpeech(text, voice: voice);
        if (path != null) {
          debugPrint('[DefaultTTS] OpenAIAdapter success: $path');
          return path;
        } else {
          debugPrint('[DefaultTTS] OpenAIAdapter returned null');
        }
      } else {
        debugPrint('[DefaultTTS] Using GeminiAdapter for model: $modelToUse');
        final adapter = GeminiAdapter(modelId: modelToUse, runtime: runtime);
        final path = await adapter.textToSpeech(text, voice: voice);
        if (path != null) {
          debugPrint('[DefaultTTS] GeminiAdapter success: $path');
          return path;
        } else {
          debugPrint('[DefaultTTS] GeminiAdapter returned null');
        }
      }
    } catch (e) {
      debugPrint('[DefaultTTS] Runtime adapter error: $e');
    }

    return null;
  }
}
