import 'package:ai_chan/shared/domain/interfaces/cross_context_interfaces.dart';
import 'package:ai_chan/call/infrastructure/services/android_native_tts_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';
import 'dart:io' show Platform;

/// Implementation of ITextToSpeechService that delegates to available TTS services
class TextToSpeechService implements ITextToSpeechService {
  final AndroidNativeTtsService _androidService = AndroidNativeTtsService();
  final GoogleSpeechService _googleService = GoogleSpeechService();

  String _currentProvider = 'android_native'; // Default to native

  @override
  Future<void> speak(
    final String text, {
    final String? language,
    final double? rate,
    final double? pitch,
  }) async {
    switch (_currentProvider) {
      case 'android_native':
        if (Platform.isAndroid) {
          // Use synthesizeToFile and play the result
          final filePath = await _androidService.synthesizeToFile(
            text: text,
            options: {
              'languageCode': language ?? 'es-ES',
              'pitch': pitch ?? 1.0,
              'speechRate': rate ?? 0.5,
            },
          );
          if (filePath != null) {
            // TODO: Play the generated file
            // This would require audio playback service integration
          }
        } else {
          // Fallback to Google on non-Android platforms
          await _googleService.textToSpeechFile(
            text: text,
            languageCode: language ?? 'es-ES',
            voiceName: 'es-ES-Neural2-A',
          );
        }
        break;
      case 'google':
        await _googleService.textToSpeechFile(
          text: text,
          languageCode: language ?? 'es-ES',
          voiceName: 'es-ES-Neural2-A',
        );
        break;
      default:
        throw UnsupportedError('Unsupported TTS provider: $_currentProvider');
    }
  }

  @override
  Future<void> stop() async {
    // TODO: Implement stop functionality
    // This would require tracking active audio playback and stopping it
  }

  @override
  Future<bool> isSpeaking() async {
    // TODO: Implement speaking status check
    // This would require tracking audio playback state
    return false;
  }

  /// Set the TTS provider to use
  void setProvider(final String provider) {
    if (['android_native', 'google'].contains(provider)) {
      _currentProvider = provider;
    }
  }

  /// Get available providers
  List<String> getAvailableProviders() {
    final providers = <String>[];
    if (Platform.isAndroid) {
      providers.add('android_native');
    }
    if (GoogleSpeechService.isConfiguredStatic) {
      providers.add('google');
    }
    return providers;
  }
}
