import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/services/gemini_service.dart';

class GeminiAdapter implements IAIService {
  final GeminiService _impl = GeminiService();

  @override
  Future<List<String>> getAvailableModels() => _impl.getAvailableModels();

  @override
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  }) async {
    final model = options?['model'] as String?;
    final imageBase64 = options?['imageBase64'] as String?;
    final imageMimeType = options?['imageMimeType'] as String?;
    final enableImageGeneration = options?['enableImageGeneration'] as bool? ?? false;

    final response = await _impl.sendMessageImpl(
      messages.cast<Map<String, String>>(),
      options?['systemPromptObj'] as dynamic,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    return response.toJson();
  }

  @override
  Future<String?> textToSpeech(String text, {String voice = 'sage'}) async {
    // GeminiService currently does not support TTS in this project.
    return null;
  }
}
