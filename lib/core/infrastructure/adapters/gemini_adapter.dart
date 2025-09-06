import 'package:ai_chan/shared/services/ai_runtime_provider.dart'
    as runtime_factory;
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/config.dart';

class GeminiAdapter implements IAIService {
  const GeminiAdapter({final String? modelId, this.runtime})
    : modelId = modelId ?? '';
  final String modelId;
  final dynamic runtime;

  dynamic get _impl {
    final resolvedModel = modelId.isNotEmpty
        ? modelId
        : (Config.getDefaultImageModel().isNotEmpty
              ? Config.getDefaultImageModel()
              : 'gemini-2.5-flash');
    return runtime ??
        runtime_factory.getRuntimeAIServiceForModel(resolvedModel);
  }

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      return await _impl.getAvailableModels();
    } on Exception catch (_) {
      return <String>[];
    }
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required final List<Map<String, dynamic>> messages,
    final Map<String, dynamic>? options,
  }) async {
    try {
      final model = options?['model'] as String?;
      final imageBase64 = options?['imageBase64'] as String?;
      final imageMimeType = options?['imageMimeType'] as String?;
      final enableImageGeneration =
          options?['enableImageGeneration'] as bool? ?? false;

      final resp = await _impl.sendMessageImpl(
        messages.cast<Map<String, String>>(),
        options?['systemPromptObj'] as dynamic,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      return (resp?.toJson() ?? <String, dynamic>{}) as Map<String, dynamic>;
    } on Exception {
      return {'text': ''};
    }
  }

  @override
  Future<String?> textToSpeech(
    final String text, {
    final String voice = '',
    final Map<String, dynamic>? options,
  }) async {
    try {
      final file = await _impl.textToSpeech(text: text, voice: voice);
      return file?.path;
    } on Exception catch (_) {
      return null;
    }
  }
}
