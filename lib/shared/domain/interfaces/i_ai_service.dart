import 'package:ai_chan/shared/domain/models/index.dart';

/// Shared domain interface for AI service operations.
/// Provides abstraction for AI message sending and response handling across bounded contexts.
abstract class IAIService {
  /// Sends a message to the AI service with the given parameters.
  /// Returns a domain `Message` with the AI's reply.
  Future<Message> sendMessage(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    required final String model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  });
}
