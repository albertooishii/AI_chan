import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared.dart' as infra;

abstract class IAIImageFactory {
  AiImage fromAIResponse({required final infra.AIResponse response});
}

class AiImageFactory implements IAIImageFactory {
  @override
  AiImage fromAIResponse({required final infra.AIResponse response}) {
    // AIResponse must contain an `imageFileName` produced by the manager
    // (the manager persists provider base64 payloads and returns filenames).
    if (response.imageFileName.isEmpty) {
      throw Exception(
        'AIResponse missing imageFileName. Ensure the AIProviderManager persisted the image binary.',
      );
    }

    return AiImage(
      seed: response.seed,
      prompt: response.prompt,
      url: response.imageFileName,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
