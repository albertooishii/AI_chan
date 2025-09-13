import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/chat/application/mappers/message_factory.dart';

class ChatMessageService {
  ChatMessageService(this._manager, this._factory);
  final AIProviderManager _manager;
  final IMessageFactory _factory;

  Future<Message> sendAndBuildMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    final MessageSender sender = MessageSender.assistant,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    final response = await _manager.sendMessage(
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

    return _factory.fromAIResponse(response: response, sender: sender);
  }
}
