import 'dart:io';
import 'dart:typed_data';
import '../../interfaces/voice_services.dart';
import '../google_speech_service.dart';

/// Implementación de TTS usando Google Cloud Text-to-Speech
class GoogleTTSService implements TTSService {
  @override
  Future<Uint8List?> textToSpeech({required String text, Map<String, dynamic>? options}) async {
    final config = GoogleSpeechService.getVoiceConfig();

    return await GoogleSpeechService.textToSpeech(
      text: text,
      languageCode: options?['languageCode'] ?? config['languageCode'],
      voiceName: options?['voiceName'] ?? config['voiceName'],
      audioEncoding: options?['audioEncoding'] ?? 'MP3',
      speakingRate: options?['speakingRate'] ?? config['speakingRate'],
      pitch: options?['pitch'] ?? config['pitch'],
    );
  }

  @override
  Future<File?> textToSpeechFile({required String text, String? fileName, Map<String, dynamic>? options}) async {
    final config = GoogleSpeechService.getVoiceConfig();

    return await GoogleSpeechService.textToSpeechFile(
      text: text,
      customFileName: fileName,
      languageCode: options?['languageCode'] ?? config['languageCode'],
      voiceName: options?['voiceName'] ?? config['voiceName'],
      audioEncoding: options?['audioEncoding'] ?? 'MP3',
      speakingRate: options?['speakingRate'] ?? config['speakingRate'],
      pitch: options?['pitch'] ?? config['pitch'],
    );
  }

  @override
  bool get isAvailable => GoogleSpeechService.isConfigured;

  @override
  Map<String, dynamic> getConfig() => GoogleSpeechService.getVoiceConfig();
}

/// Implementación de STT usando Google Cloud Speech-to-Text
class GoogleSTTService implements STTService {
  @override
  Future<String?> speechToText({required Uint8List audioData, Map<String, dynamic>? options}) async {
    return await GoogleSpeechService.speechToText(
      audioData: audioData,
      languageCode: options?['languageCode'] ?? 'es-ES',
      audioEncoding: options?['audioEncoding'] ?? 'WEBM_OPUS',
      sampleRateHertz: options?['sampleRateHertz'] ?? 48000,
      enableAutomaticPunctuation: options?['enableAutomaticPunctuation'] ?? true,
    );
  }

  @override
  Future<String?> speechToTextFromFile({required File audioFile, Map<String, dynamic>? options}) async {
    return await GoogleSpeechService.speechToTextFromFile(
      audioFile,
      languageCode: options?['languageCode'] ?? 'es-ES',
      audioEncoding: options?['audioEncoding'] ?? 'MP3',
      sampleRateHertz: options?['sampleRateHertz'] ?? 24000,
    );
  }

  @override
  bool get isAvailable => GoogleSpeechService.isConfigured;

  @override
  Map<String, dynamic> getConfig() {
    return {
      'languageCode': 'es-ES',
      'audioEncoding': 'WEBM_OPUS',
      'sampleRateHertz': 48000,
      'enableAutomaticPunctuation': true,
    };
  }
}
