import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/models.dart' as infra;

abstract class IMessageFactory {
  Message fromAIResponse({
    required final infra.AIResponse response,
    required final MessageSender sender,
    final DateTime? dateTime,
    final String? localId,
  });
}

class MessageFactory implements IMessageFactory {
  @override
  Message fromAIResponse({
    required final infra.AIResponse response,
    required final MessageSender sender,
    final DateTime? dateTime,
    final String? localId,
  }) {
    final DateTime now = dateTime ?? DateTime.now();

    AiImage? aiImage;
    if (response.imageFileName.isNotEmpty) {
      aiImage = AiImage(
        seed: response.seed,
        prompt: response.prompt,
        url: response.imageFileName,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    return Message(
      text: response.text,
      sender: sender,
      dateTime: now,
      isImage: aiImage != null,
      image: aiImage,
      status: MessageStatus.sent,
      localId: localId,
    );
  }
}
