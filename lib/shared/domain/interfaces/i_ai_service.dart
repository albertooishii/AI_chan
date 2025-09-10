import 'package:ai_chan/core/models.dart';

/// Shared domain interface for AI service operations.
/// Provides abstraction for AI message sending and response handling across bounded contexts.
abstract class IAIService {
  /// Sends a message to the AI service with the given parameters.
  /// Returns an AIResponse with the AI's reply.
  Future<AIResponse> sendMessage(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    required final String model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  });
}
