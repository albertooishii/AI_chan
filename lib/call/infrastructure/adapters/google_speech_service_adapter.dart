import 'dart:typed_data';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';

/// Adaptador que implementa ISpeechService usando GoogleSpeechService
class GoogleSpeechServiceAdapter implements ISpeechService {
  @override
  Future<Uint8List> textToSpeech({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    final result = await GoogleSpeechService.textToSpeechStatic(
      text: text,
      voiceName: voice == 'default' ? 'es-ES-Wavenet-F' : voice,
      speakingRate: speed,
    );
    return result ?? Uint8List(0);
  }

  @override
  Future<List<String>> getAvailableVoices() async {
    // Google Speech Service has complex voice structure, return simple list
    return [
      'es-ES-Standard-A',
      'es-ES-Standard-B',
      'es-ES-Standard-C',
      'es-ES-Standard-D',
      'es-ES-Wavenet-A',
      'es-ES-Wavenet-B',
      'es-ES-Wavenet-C',
      'es-ES-Wavenet-D',
    ];
  }

  @override
  Future<bool> isAvailable() async {
    return GoogleSpeechService.isConfiguredStatic;
  }
}
