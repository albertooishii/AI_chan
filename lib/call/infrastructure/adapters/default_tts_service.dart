import 'dart:io';
import 'package:ai_chan/call/infrastructure/services/android_native_tts_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:flutter/foundation.dart';

// dotenv usage removed — use Config getters instead
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/constants/openai_voices.dart';

/// Default TTS service that tries native -> Google -> OpenAI in that order.
class DefaultTtsService implements ICallTtsService {
  const DefaultTtsService();

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    // Merge available voices from Android native (if any) and Google TTS.
    final List<Map<String, dynamic>> voices = [];
    try {
      final native = await AndroidNativeTtsService.getAvailableVoicesStatic();
      voices.addAll(native);
    } on Exception catch (_) {}
    try {
      final google = await GoogleSpeechService.fetchGoogleVoicesStatic();
      voices.addAll(google.cast<Map<String, dynamic>>());
    } on Exception catch (_) {}
    return voices;
  }

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    var voice = options?['voice'] as String? ?? 'marin';
    final languageCode = options?['languageCode'] as String? ?? 'es-ES';
    final explicitProvider = options?['provider'] as String?;

    debugPrint(
      '[DefaultTTS] synthesizeToFile called - voice: $voice, languageCode: $languageCode, explicitProvider: $explicitProvider',
    );

    // Determine provider respecting explicit parameter first:
    // 1. Use explicit provider from options (highest priority)
    // 2. Use configured provider from prefs/env
    // 3. If no config -> use default fallback
    String provider;

    if (explicitProvider != null && explicitProvider.isNotEmpty) {
      provider = explicitProvider.toLowerCase();
      debugPrint(
        '[DefaultTTS] Using explicit provider from options: $provider for voice: $voice',
      );
    } else {
      try {
        provider = await PrefsUtils.getSelectedAudioProvider();
        debugPrint(
          '[DefaultTTS] Using configured provider: $provider for voice: $voice',
        );
      } on Exception catch (_) {
        // Fallback to env config
        final env = Config.getAudioProvider().toLowerCase();
        provider = (env == 'openai')
            ? 'openai'
            : (env == 'gemini')
            ? 'google'
            : env.isNotEmpty
            ? env
            : 'google';
        debugPrint(
          '[DefaultTTS] Using env config provider: $provider for voice: $voice',
        );
      }
    }

    // Handle auto-detection only if explicitly set to auto
    if (provider == 'auto' || provider.isEmpty) {
      provider = 'google'; // Default fallback
      debugPrint(
        '[DefaultTTS] Auto-detection defaulting to: $provider for voice: $voice',
      );
    }

    debugPrint('[DefaultTTS] Using provider: $provider for voice: $voice');

    // 1) Try Android native TTS when available (mobile-first behaviour kept) - ONLY for non-OpenAI and non-Google Cloud voices
    if (provider != 'openai' && provider != 'google') {
      debugPrint(
        '[DefaultTTS] Trying Android native TTS for non-OpenAI/non-Google voice: $voice',
      );
      try {
        if (AndroidNativeTtsService.isAndroid) {
          final isNativeAvailable =
              await AndroidNativeTtsService.checkNativeTtsAvailable();
          if (isNativeAvailable) {
            try {
              final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
              if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
              final outputPath =
                  '${baseTmp.path}/ai_chan_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
              final res = await AndroidNativeTtsService.synthesizeToFileStatic(
                text: text,
                outputPath: outputPath,
                voiceName: voice,
                languageCode: languageCode,
              );
              if (res != null) {
                debugPrint('[DefaultTTS] Android native TTS success: $res');
                return res;
              }
            } on Exception catch (e) {
              debugPrint('[DefaultTTS] Android native TTS error: $e');
            }
          }
        }
      } on Exception catch (e) {
        debugPrint('[DefaultTTS] Android native TTS exception: $e');
      }
    } else if (provider == 'openai') {
      debugPrint(
        '[DefaultTTS] Skipping Android native TTS for OpenAI voice: $voice',
      );
    } else if (provider == 'google') {
      debugPrint(
        '[DefaultTTS] Skipping Android native TTS for Google Cloud voice: $voice',
      );
    }

    // 2) Try Google TTS when configured or selected.
    // If the provider was explicitly chosen as Google, map generic or OpenAI
    // voice names to the configured GOOGLE_VOICE_NAME before calling the API.
    if (provider == 'google') {
      debugPrint('[DefaultTTS] Trying Google TTS for voice: $voice');

      // Normalize voice: if caller passed an OpenAI voice name or empty string,
      // substitute Google default voice from .env when available.
      if (voice.trim().isEmpty || kOpenAIVoices.contains(voice)) {
        final googleDefault = Config.getGoogleVoice();
        if (googleDefault.isNotEmpty) {
          debugPrint(
            '[DefaultTTS] Mapping voice "$voice" -> Google default voice: $googleDefault',
          );
          voice = googleDefault;
        } else {
          debugPrint(
            '[DefaultTTS] No GOOGLE_VOICE_NAME defined in env to map voice "$voice" for provider google',
          );
        }
      }

      try {
        if (GoogleSpeechService.isConfiguredStatic) {
          final file = await GoogleSpeechService.textToSpeechFileStatic(
            text: text,
            voiceName: voice,
            languageCode: languageCode,
          );
          if (file != null) {
            debugPrint('[DefaultTTS] Google TTS success: $file');
            return file;
          }

          debugPrint('[DefaultTTS] Google TTS returned null');

          // If provider was explicitly chosen, don't silently fallback to other
          // providers when Google was explicitly requested and it returned null.
          // If Google returned null we continue to fallbacks — no explicit provider flag
        } else {
          debugPrint('[DefaultTTS] Google TTS not configured');
        }
      } on Exception catch (e) {
        debugPrint('[DefaultTTS] Google TTS error: $e');
        // If the error indicates an invalid voice and provider was explicitly
        // chosen, abort fallback to avoid using a different provider's voice.
        // If Google TTS error indicates invalid voice we allow fallback to other adapters.
      }
    }

    // 2.5) Direct OpenAI handling for OpenAI voices
    if (provider == 'openai') {
      debugPrint(
        '[DefaultTTS] Trying direct OpenAI handling for voice: $voice',
      );
      try {
        // Enhanced AI system doesn't support TTS yet - skip for now
        debugPrint('[DefaultTTS] Enhanced AI TTS not implemented yet');
      } on Exception catch (e) {
        debugPrint('[DefaultTTS] Enhanced AI error: $e');
      }
    }

    // 3) Fallback to a runtime adapter using centralized runtime factory.
    // Project-wide default is Gemini ('gemini-2.5-flash'). If the chosen provider is OpenAI,
    // we prefer 'gpt-4.1-mini'. Otherwise use DEFAULT_TEXT_MODEL when configured.
    try {
      final defaultModel = Config.getDefaultTextModel();
      final String modelToUse = defaultModel.isNotEmpty
          ? defaultModel
          : (provider == 'openai'
                ? (Config.getDefaultTextModel().isNotEmpty
                      ? Config.getDefaultTextModel()
                      : 'gpt-4.1-mini')
                : (Config.getDefaultTextModel().isNotEmpty
                      ? Config.getDefaultTextModel()
                      : 'gemini-2.5-flash'));

      debugPrint(
        '[DefaultTTS] Fallback to Enhanced AI - provider: $provider, voice: $voice, modelToUse: $modelToUse',
      );

      // Enhanced AI TTS not implemented yet - skip fallback
      debugPrint('[DefaultTTS] Enhanced AI TTS fallback not implemented yet');

      return null; // No TTS path available from Enhanced AI yet
    } on Exception catch (e) {
      debugPrint('[DefaultTTS] Runtime adapter error: $e');
    }

    return null;
  }

  // Implementación de ITtsAdapter
  @override
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    try {
      // DefaultTtsService se enfoca en archivos, no en bytes directos
      // Retornamos bytes vacíos para indicar que no es compatible
      return Uint8List(0);
    } on Exception catch (e) {
      debugPrint('[DefaultTtsService] synthesize error: $e');
      return Uint8List(0);
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[DefaultTtsService] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    // DefaultTtsService siempre está disponible como fallback
    return true;
  }
}
