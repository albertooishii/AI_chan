import 'dart:async';
import 'package:ai_chan/shared/domain/interfaces/cross_context_interfaces.dart';

/// Application service for STT operations
/// This service acts as a facade between presentation and infrastructure
class SttApplicationService {
  SttApplicationService(this._sttService);
  final ISpeechToTextService _sttService;

  /// Start listening for speech
  Future<void> startListening({final String? language}) async {
    await _sttService.startListening(language: language);
  }

  /// Stop listening for speech
  Future<void> stopListening() async {
    await _sttService.stopListening();
  }

  /// Get stream of recognized text
  Stream<String> get onTextReceived => _sttService.onTextReceived;

  /// Check if STT service is available
  Future<bool> isAvailable() async {
    return _sttService.isAvailable();
  }

  /// Process audio file for speech-to-text
  Future<String?> processAudioFile(
    final String audioFilePath, {
    final String? language,
  }) async {
    // This would need to be implemented in the infrastructure service
    // For now, return null
    return null;
  }
}
