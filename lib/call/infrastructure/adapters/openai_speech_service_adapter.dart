import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/openai_speech_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:flutter/foundation.dart';

/// Adapter que implementa ISpeechService usando OpenAISpeechService
class OpenAISpeechServiceAdapter implements ISpeechService {
  @override
  Future<Uint8List> textToSpeech({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    try {
      // OpenAISpeechService parece ser principalmente para metadatos de voces
      // No tiene síntesis directa, retornamos vacío
      debugPrint(
        '[OpenAISpeechServiceAdapter] textToSpeech not implemented - use OpenAI TTS via other services',
      );
      return Uint8List(0);
    } on Exception catch (e) {
      debugPrint('[OpenAISpeechServiceAdapter] textToSpeech error: $e');
      return Uint8List(0);
    }
  }

  @override
  Future<List<String>> getAvailableVoices() async {
    try {
      final voices = await OpenAISpeechService.fetchOpenAIVoicesStatic();
      return voices
          .map((final voice) => voice['name'] as String? ?? 'unknown')
          .toList();
    } on Exception catch (e) {
      debugPrint('[OpenAISpeechServiceAdapter] getAvailableVoices error: $e');
      return [];
    }
  }

  void configure(final Map<String, dynamic> config) {
    debugPrint('[OpenAISpeechServiceAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    try {
      // Verificar si hay API key de OpenAI disponible
      return Config.getOpenAIKey().isNotEmpty;
    } on Exception catch (_) {
      return false;
    }
  }
}
