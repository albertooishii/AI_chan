import 'package:ai_chan/shared.dart';
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
    final AiImage? imageRef,
    final bool enableImageGeneration = false,
  }) async {
    // If the caller provided an AiImage reference (`imageRef.url`), load the
    // persisted base64 centrally and forward it to the manager as `imageBase64`.
    String? resolvedImageBase64;
    if (imageRef != null && imageRef.url != null && imageRef.url!.isNotEmpty) {
      resolvedImageBase64 = await ImagePersistenceService.instance
          .loadImageAsBase64(imageRef.url!);
    }

    final response = await _manager.sendMessage(
      history: history,
      systemPrompt: systemPrompt,
      capability: enableImageGeneration
          ? AICapability.imageGeneration
          : (imageBase64 != null
                ? AICapability.imageAnalysis
                : AICapability.textGeneration),
      imageBase64: imageBase64 ?? resolvedImageBase64,
      imageMimeType: imageMimeType,
    );

    return _factory.fromAIResponse(response: response, sender: sender);
  }
}
