import 'package:ai_chan/shared/domain/interfaces/cross_context_interfaces.dart';

/// Application service for TTS operations
/// This service acts as a facade between presentation and infrastructure
class TtsApplicationService {
  TtsApplicationService(this._ttsService);
  final ITextToSpeechService _ttsService;

  /// Speak text using the configured TTS service
  Future<void> speakText(
    final String text, {
    final String? language,
    final double? rate,
    final double? pitch,
  }) async {
    await _ttsService.speak(text, language: language, rate: rate, pitch: pitch);
  }

  /// Stop current speech
  Future<void> stopSpeech() async {
    await _ttsService.stop();
  }

  /// Check if TTS is currently speaking
  Future<bool> isSpeaking() async {
    return _ttsService.isSpeaking();
  }

  /// Get available TTS providers
  List<String> getAvailableProviders() {
    // This would need to be implemented in the infrastructure service
    // For now, return default providers
    return ['android_native', 'google'];
  }

  /// Set the TTS provider
  void setProvider(final String provider) {
    // This would need to be implemented in the infrastructure service
    // For now, this is a placeholder
  }
}
