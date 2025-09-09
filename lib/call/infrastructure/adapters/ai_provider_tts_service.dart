import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/android_native_tts_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/core/models/system_prompt.dart';
import 'package:ai_chan/shared/constants/openai_voices.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:flutter/foundation.dart';

/// Modern TTS service using AIProviderManager with fallback to native/Google TTS
class AIProviderTtsService implements ICallTtsService {
  const AIProviderTtsService();

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
    var voice = options?['voice'] as String? ?? 'alloy';
    final languageCode = options?['languageCode'] as String? ?? 'es-ES';
    final explicitProvider = options?['provider'] as String?;

    debugPrint(
      '[AIProviderTtsService] synthesizeToFile called - voice: $voice, languageCode: $languageCode, explicitProvider: $explicitProvider',
    );

    // Determine provider respecting explicit parameter first:
    String provider;

    if (explicitProvider != null && explicitProvider.isNotEmpty) {
      provider = explicitProvider.toLowerCase();
      debugPrint(
        '[AIProviderTtsService] Using explicit provider from options: $provider for voice: $voice',
      );
    } else {
      try {
        provider = await PrefsUtils.getSelectedAudioProvider();
        debugPrint(
          '[AIProviderTtsService] Using configured provider: $provider for voice: $voice',
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
            : 'openai'; // Default to OpenAI since it has good TTS support
        debugPrint(
          '[AIProviderTtsService] Using env config provider: $provider for voice: $voice',
        );
      }
    }

    // Handle auto-detection only if explicitly set to auto
    if (provider == 'auto' || provider.isEmpty) {
      provider = 'openai'; // Default to OpenAI for TTS
      debugPrint(
        '[AIProviderTtsService] Auto-detection defaulting to: $provider for voice: $voice',
      );
    }

    debugPrint(
      '[AIProviderTtsService] Using provider: $provider for voice: $voice',
    );

    // 1) Try Android native TTS when available (mobile-first behaviour kept) - ONLY for non-OpenAI and non-Google Cloud voices
    if (provider != 'openai' && provider != 'google') {
      debugPrint(
        '[AIProviderTtsService] Trying Android native TTS for non-OpenAI/non-Google voice: $voice',
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
                debugPrint(
                  '[AIProviderTtsService] Android native TTS success: $res',
                );
                return res;
              }
            } on Exception catch (e) {
              debugPrint('[AIProviderTtsService] Android native TTS error: $e');
            }
          }
        }
      } on Exception catch (e) {
        debugPrint('[AIProviderTtsService] Android native TTS exception: $e');
      }
    }

    // 2) Try Google TTS when configured or selected.
    if (provider == 'google') {
      debugPrint('[AIProviderTtsService] Trying Google TTS for voice: $voice');

      // Normalize voice: if caller passed an OpenAI voice name, substitute Google default voice
      if (voice.trim().isEmpty || kOpenAIVoices.contains(voice)) {
        final googleDefault = Config.getGoogleVoice();
        if (googleDefault.isNotEmpty) {
          debugPrint(
            '[AIProviderTtsService] Mapping voice "$voice" -> Google default voice: $googleDefault',
          );
          voice = googleDefault;
        } else {
          debugPrint(
            '[AIProviderTtsService] No GOOGLE_VOICE_NAME defined in env to map voice "$voice" for provider google',
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
            debugPrint('[AIProviderTtsService] Google TTS success: $file');
            return file;
          }
          debugPrint('[AIProviderTtsService] Google TTS returned null');
        } else {
          debugPrint('[AIProviderTtsService] Google TTS not configured');
        }
      } on Exception catch (e) {
        debugPrint('[AIProviderTtsService] Google TTS error: $e');
      }
    }

    // 3) Try AIProviderManager for TTS (OpenAI or other providers that support audioGeneration)
    try {
      debugPrint(
        '[AIProviderTtsService] Trying AIProviderManager for TTS - provider: $provider, voice: $voice',
      );

      // Ensure AIProviderManager is initialized before checking capabilities
      if (!AIProviderManager.instance.isInitialized) {
        debugPrint(
          '[AIProviderTtsService] AIProviderManager not initialized, initializing...',
        );
        await AIProviderManager.instance.initialize();
      }

      // Check if any provider supports audio generation
      final audioProviders = AIProviderManager.instance
          .getProvidersByCapability(AICapability.audioGeneration);

      if (audioProviders.isNotEmpty) {
        // Create a simple history for TTS
        final history = [
          {'role': 'user', 'content': text},
        ];

        // Create a minimal system prompt for TTS
        final dummyProfile = AiChanProfile(
          userName: 'TTS',
          aiName: 'AI',
          userBirthdate: DateTime.now(),
          aiBirthdate: DateTime.now(),
          appearance: {},
          biography: {},
        );
        final systemPrompt = SystemPrompt(
          profile: dummyProfile,
          dateTime: DateTime.now(),
          instructions: {
            'raw':
                'Generate audio speech from the given text using the specified voice.',
          },
        );

        final response = await AIProviderManager.instance.sendMessage(
          history: history,
          systemPrompt: systemPrompt,
          capability: AICapability.audioGeneration,
          additionalParams: {'voice': voice, 'language_code': languageCode},
        );

        debugPrint(
          '[AIProviderTtsService] AIProviderManager response received:',
        );
        debugPrint('  - text: "${response.text}"');
        debugPrint('  - base64.isNotEmpty: ${response.base64.isNotEmpty}');
        debugPrint('  - base64.length: ${response.base64.length}');

        if (response.base64.isNotEmpty) {
          // Save the base64 audio to a temporary file
          final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
          if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
          final outputPath =
              '${baseTmp.path}/ai_chan_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';

          final audioBytes = base64Decode(response.base64);
          final file = File(outputPath);
          await file.writeAsBytes(audioBytes);

          debugPrint(
            '[AIProviderTtsService] AIProviderManager TTS success: $outputPath',
          );
          return outputPath;
        } else {
          debugPrint(
            '[AIProviderTtsService] AIProviderManager TTS returned no audio data',
          );
        }
      } else {
        debugPrint(
          '[AIProviderTtsService] No providers support audioGeneration capability',
        );
      }
    } on Exception catch (e) {
      debugPrint('[AIProviderTtsService] AIProviderManager TTS error: $e');
    }

    debugPrint('[AIProviderTtsService] All TTS methods failed');
    return null;
  }

  @override
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'alloy',
    final double speed = 1.0,
  }) async {
    try {
      debugPrint(
        '[AIProviderTtsService] synthesize called - voice: $voice, speed: $speed',
      );

      // Ensure AIProviderManager is initialized before checking capabilities
      if (!AIProviderManager.instance.isInitialized) {
        debugPrint(
          '[AIProviderTtsService] AIProviderManager not initialized, initializing...',
        );
        await AIProviderManager.instance.initialize();
      }

      // Check if any provider supports audio generation
      final audioProviders = AIProviderManager.instance
          .getProvidersByCapability(AICapability.audioGeneration);

      if (audioProviders.isNotEmpty) {
        // Create a simple history for TTS
        final history = [
          {'role': 'user', 'content': text},
        ];

        // Create a minimal system prompt for TTS
        final dummyProfile = AiChanProfile(
          userName: 'TTS',
          aiName: 'AI',
          userBirthdate: DateTime.now(),
          aiBirthdate: DateTime.now(),
          appearance: {},
          biography: {},
        );
        final systemPrompt = SystemPrompt(
          profile: dummyProfile,
          dateTime: DateTime.now(),
          instructions: {
            'raw':
                'Generate audio speech from the given text using the specified voice.',
          },
        );

        final response = await AIProviderManager.instance.sendMessage(
          history: history,
          systemPrompt: systemPrompt,
          capability: AICapability.audioGeneration,
          additionalParams: {'voice': voice, 'speed': speed},
        );

        if (response.base64.isNotEmpty) {
          final audioBytes = base64Decode(response.base64);
          debugPrint(
            '[AIProviderTtsService] synthesize success - ${audioBytes.length} bytes',
          );
          return audioBytes;
        } else {
          debugPrint(
            '[AIProviderTtsService] synthesize returned no audio data',
          );
        }
      } else {
        debugPrint(
          '[AIProviderTtsService] No providers support audioGeneration capability',
        );
      }

      return Uint8List(0);
    } on Exception catch (e) {
      debugPrint('[AIProviderTtsService] synthesize error: $e');
      return Uint8List(0);
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[AIProviderTtsService] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    // Check if we have any TTS capability available
    final audioProviders = AIProviderManager.instance.getProvidersByCapability(
      AICapability.audioGeneration,
    );
    final hasAndroidNative = AndroidNativeTtsService.isAndroid;
    final hasGoogleTts = GoogleSpeechService.isConfiguredStatic;

    return audioProviders.isNotEmpty || hasAndroidNative || hasGoogleTts;
  }
}
