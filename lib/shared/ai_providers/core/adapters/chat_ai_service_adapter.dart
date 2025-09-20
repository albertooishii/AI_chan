import 'package:ai_chan/shared.dart';
import 'package:ai_chan/chat.dart';

/// Infrastructure adapter implementing chat AI service using the new AI Provider system.
/// Directly uses AIProviderManager without legacy compatibility layers.
class ChatAIServiceAdapter implements IAIService {
  const ChatAIServiceAdapter([this._service]);
  final ChatMessageService? _service;

  @override
  Future<Message> sendMessage(
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

      // Delegate to ChatMessageService (preferred) or fallback to direct manager
      if (_service != null) {
        return await _service.sendAndBuildMessage(
          history: history,
          systemPrompt: systemPrompt,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          enableImageGeneration: enableImageGeneration,
        );
      }

      // Fallback: call manager and map to Message via implicit factory
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

      // Use the MessageFactory directly to convert (create a temporary one)
      final factory = MessageFactory();
      return factory.fromAIResponse(
        response: response,
        sender: MessageSender.assistant,
      );
    } on Exception catch (e) {
      // Log errors
      await debugLogCallPrompt('chat_ai_service_direct_error', {
        'error': e.toString(),
        'model': model,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Return error Message
      return Message(
        text: 'Error in direct AI service: $e',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
      );
    }
  }
}
