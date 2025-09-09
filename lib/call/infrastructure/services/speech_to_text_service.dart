import 'dart:async';
import 'package:ai_chan/shared/domain/interfaces/cross_context_interfaces.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';

/// Implementation of ISpeechToTextService using Google Speech-to-Text
class SpeechToTextService implements ISpeechToTextService {
  final GoogleSpeechService _googleService = GoogleSpeechService();

  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  bool _isListening = false;

  @override
  Future<void> startListening({final String? language}) async {
    if (_isListening) return;

    _isListening = true;
    // TODO: Implement continuous listening using Google Speech API
    // This would require setting up a continuous recognition session
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    // TODO: Stop the recognition session
  }

  @override
  Stream<String> get onTextReceived => _textController.stream;

  @override
  Future<bool> isAvailable() async {
    return GoogleSpeechService.isConfiguredStatic;
  }

  /// Process a single audio file for speech-to-text
  Future<String?> processAudioFile(
    final String audioFilePath, {
    final String? language,
  }) async {
    try {
      return await _googleService.speechToTextFromFile(
        audioFilePath,
        languageCode: language ?? 'es-ES',
      );
    } on Exception {
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _textController.close();
  }
}
