import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;
import 'package:ai_chan/core/interfaces/ai_service.dart';

/// Thin adapter that implements the legacy IAIService port and delegates to
/// the runtime instance created by runtime_factory. This keeps DI stable
/// while allowing runtimes to be created centrally.
class OpenAIAdapter implements IAIService {
  final String modelId;
  OpenAIAdapter({this.modelId = 'gpt-4o'});

  dynamic get _impl => runtime_factory.getRuntimeAIServiceForModel(modelId);

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      return await _impl.getAvailableModels();
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  }) async {
    try {
      final model = options?['model'] as String?;
      final imageBase64 = options?['imageBase64'] as String?;
      final imageMimeType = options?['imageMimeType'] as String?;
      final enableImageGeneration = options?['enableImageGeneration'] as bool? ?? false;

      final resp = await _impl.sendMessageImpl(
        messages.cast<Map<String, String>>(),
        options?['systemPromptObj'] as dynamic,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      return (resp?.toJson() ?? <String, dynamic>{}) as Map<String, dynamic>;
    } catch (e) {
      return {'text': ''};
    }
  }

  @override
  Future<String?> textToSpeech(String text, {String voice = ''}) async {
    try {
      final file = await _impl.textToSpeech(text: text, voice: voice);
      return file?.path;
    } catch (_) {
      return null;
    }
  }
}

