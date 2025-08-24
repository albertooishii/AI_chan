import 'dart:async';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

/// Fake simple que permite configurar secuencia de respuestas para sendMessageImpl
class FakeAIService implements AIService {
  final List<AIResponse> responses;
  int _idx = 0;

  FakeAIService(this.responses);

  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    // Simular latencia pequeña
    await Future.delayed(Duration(milliseconds: 30));
    if (_idx >= responses.length) {
      return AIResponse(text: '');
    }
    final r = responses[_idx];
    _idx++;
    return r;
  }

  @override
  Future<List<String>> getAvailableModels() async => ['test-model'];
}
