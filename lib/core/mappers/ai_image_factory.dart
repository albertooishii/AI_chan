import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/models.dart' as infra;

abstract class IAIImageFactory {
  AiImage fromAIResponse({required final infra.AIResponse response});
}

class AiImageFactory implements IAIImageFactory {
  @override
  AiImage fromAIResponse({required final infra.AIResponse response}) {
    if (response.imageFileName.isEmpty) {
      throw Exception('AIResponse does not contain imageFileName');
    }

    return AiImage(
      seed: response.seed,
      prompt: response.prompt,
      url: response.imageFileName,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
