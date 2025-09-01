import 'dart:convert';

import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';

/// Fake AIService used in tests to replace the runtime via AIService.testOverride
class FakeAIService extends AIService {
  bool called = false;
  final String? textResponse;
  final String? imageBase64Response;
  final bool shouldThrowError;
  final Map<String, dynamic>? customJsonResponse;
  final String errorMessage;
  final List<AIResponse>? responses;
  int _idx = 0;

  FakeAIService({
    this.responses,
    this.textResponse = 'fake response',
    this.imageBase64Response,
    this.shouldThrowError = false,
    this.customJsonResponse,
    this.errorMessage = 'AI failure',
  });

  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    called = true;
    // If a sequence of responses was provided, return them in order.
    if (responses != null) {
      if (_idx >= responses!.length) {
        return AIResponse(text: '');
      }
      final r = responses![_idx];
      _idx++;
      return r;
    }
    if (shouldThrowError) throw Exception(errorMessage);

    // Special behavior for combined appearance+biography fake
    if (_forAppearanceAndBiography) {
      if (enableImageGeneration) {
        const onePixelPngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
        return AIResponse(text: '', base64: onePixelPngBase64, seed: 'test-seed-123', prompt: 'fake-prompt');
      }
      final json = '{"resumen_breve":"Resumen de prueba","datos_personales":{"nombre_completo":"Ai Test"}}';
      return AIResponse(text: json);
    }

    if (customJsonResponse != null) {
      return AIResponse(
        text: jsonEncode(customJsonResponse),
        base64: imageBase64Response ?? '',
        seed: 'test-seed-123',
        prompt: 'fake-prompt',
      );
    }

    if (enableImageGeneration && imageBase64Response != null) {
      return AIResponse(
        text: textResponse ?? '',
        base64: imageBase64Response!,
        seed: 'test-seed-123',
        prompt: 'fake-prompt',
      );
    }

    return AIResponse(text: textResponse ?? 'fake response', seed: 'test-seed-123', prompt: 'fake-prompt');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake'];

  /// Factory for biography generation tests
  factory FakeAIService.forBiography() => FakeAIService(
    customJsonResponse: {
      'datos_personales': {'nombre_completo': 'Ai Test'},
      'personalidad': {
        'valores': {'Sociabilidad': '5'},
        'intereses': ['testing', 'coding'],
      },
      'timeline': [],
    },
  );

  /// Factory for appearance generation tests
  factory FakeAIService.forAppearance() {
    const onePixelPngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
    return FakeAIService(
      customJsonResponse: {
        'hair': {'color': 'brown', 'style': 'long'},
        'eyes': {'color': 'blue'},
      },
      imageBase64Response: onePixelPngBase64,
    );
  }

  /// Factory that returns a FakeAIService which yields the given sequence of AIResponse
  factory FakeAIService.withResponses(List<AIResponse> responses) => FakeAIService(responses: responses);

  /// Convenience factory that returns a service that replies with a simple text
  factory FakeAIService.withText(String text) => FakeAIService(textResponse: text);

  /// Convenience factory for tests that need the AI to return an audio-tagged text
  factory FakeAIService.withAudio(String audioTaggedText) => FakeAIService(textResponse: audioTaggedText);

  /// Factory that behaves like tests expect: when enableImageGeneration==true
  /// returns a 1x1 PNG base64, otherwise returns a minimal biography JSON.
  factory FakeAIService.forAppearanceAndBiography() {
    return FakeAIService().._forAppearanceAndBiography = true;
  }

  // Internal toggle used by forAppearanceAndBiography factory
  bool _forAppearanceAndBiography = false;

  /// Factory for failure scenarios
  factory FakeAIService.withError([String? message]) =>
      FakeAIService(shouldThrowError: true, errorMessage: message ?? 'AI failure');
}
