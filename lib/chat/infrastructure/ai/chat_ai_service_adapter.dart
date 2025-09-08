import 'package:ai_chan/chat/domain/interfaces/i_chat_ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

/// Infrastructure adapter implementing chat AI service using shared AIService.
/// Bridges domain interface with shared AI service functionality.
class ChatAIServiceAdapter implements IChatAIService {
  const ChatAIServiceAdapter();

  @override
  Future<AIResponse> sendMessage(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    required final String model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    return await AIService.sendMessage(
      history,
      systemPrompt,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );
  }
}
