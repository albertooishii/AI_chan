import 'package:ai_chan/core/models.dart';

/// Domain interface for AI service operations within chat bounded context.
/// Provides abstraction for AI message sending and response handling.
abstract class IChatAIService {
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
