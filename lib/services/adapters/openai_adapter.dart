import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/services/openai_service.dart';

/// Adapter that implements IAIService and delegates to the existing OpenAIService
class OpenAIAdapter implements IAIService {
  final OpenAIService _impl = OpenAIService();

  @override
  Future<List<String>> getAvailableModels() => _impl.getAvailableModels();

  @override
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  }) async {
    // Convert options to the shape expected by OpenAIService.sendMessageImpl if needed
    final model = options?['model'] as String?;
    final imageBase64 = options?['imageBase64'] as String?;
    final imageMimeType = options?['imageMimeType'] as String?;
    final enableImageGeneration = options?['enableImageGeneration'] as bool? ?? false;

    final response = await _impl.sendMessageImpl(
      messages.cast<Map<String, String>>(),
      // OpenAIService expects a SystemPrompt-like object; we assume the adapter caller passes a Map under 'systemPromptObj'
      options?['systemPromptObj'] as dynamic,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    // Convert AIResponse (internal) to a generic Map<String,dynamic>
    return response.toJson();
  }

  @override
  Future<String?> textToSpeech(String text, {String voice = 'sage'}) async {
    try {
      final file = await _impl.textToSpeech(text: text, voice: voice);
      return file?.path;
    } catch (_) {
      return null;
    }
  }
}
