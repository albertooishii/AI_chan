import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'dart:convert';

/// Base fake AI service for testing - provides configurable responses
class FakeAIService extends AIService {
  final String? textResponse;
  final String? imageBase64Response;
  final bool shouldThrowError;
  final Map<String, dynamic>? customJsonResponse;
  final String errorMessage;

  FakeAIService({
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
    if (shouldThrowError) {
      throw Exception(errorMessage);
    }

    if (customJsonResponse != null) {
      return AIResponse(
        text: jsonEncode(customJsonResponse),
        base64: imageBase64Response ?? '',
        seed: 'fake-seed',
        prompt: 'fake-prompt',
      );
    }

    if (enableImageGeneration && imageBase64Response != null) {
      return AIResponse(
        text: textResponse ?? '',
        base64: imageBase64Response!,
        seed: 'fake-seed',
        prompt: 'fake-prompt',
      );
    }

    return AIResponse(
      text: textResponse ?? 'fake response',
      base64: '',
      seed: 'fake-seed',
      prompt: 'fake-prompt',
    );
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake'];

  /// Factory for biography generation tests
  factory FakeAIService.forBiography() {
    return FakeAIService(
      customJsonResponse: {
        'datos_personales': {'nombre_completo': 'Ai Test'},
        'personalidad': {
          'valores': {'Sociabilidad': '5'},
          'intereses': ['testing', 'coding'],
        },
        'timeline': [],
      },
    );
  }

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

  /// Factory for failure scenarios
  factory FakeAIService.withError([String? message]) {
    return FakeAIService(
      shouldThrowError: true,
      errorMessage: message ?? 'AI failure',
    );
  }
}
