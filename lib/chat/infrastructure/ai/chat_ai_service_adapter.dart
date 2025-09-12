import 'package:ai_chan/shared/domain/interfaces/i_ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/utils/debug_call_logger/debug_call_logger.dart';

/// Infrastructure adapter implementing chat AI service using the new AI Provider system.
/// Directly uses AIProviderManager without legacy compatibility layers.
class ChatAIServiceAdapter implements IAIService {
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
    try {
      // Debug logging for the new direct system
      await debugLogCallPrompt('chat_ai_service_direct_send', {
        'model': model,
        'history_length': history.length,
        'has_image': imageBase64 != null,
        if (imageBase64 != null) 'image_base64_length': imageBase64.length,
        if (imageMimeType != null) 'image_mime_type': imageMimeType,
        'enable_image_generation': enableImageGeneration,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Use AIProviderManager directly with appropriate capability
      final response = await AIProviderManager.instance.sendMessage(
        history: history,
        systemPrompt: systemPrompt,
        capability: enableImageGeneration
            ? AICapability.imageGeneration
            : (imageBase64 != null
                  ? AICapability.imageAnalysis
                  : AICapability.textGeneration),
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );

      return response;
    } on Exception catch (e) {
      // Log errors
      await debugLogCallPrompt('chat_ai_service_direct_error', {
        'error': e.toString(),
        'model': model,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Return error response
      return AIResponse(text: 'Error in direct AI service: $e');
    }
  }
}
