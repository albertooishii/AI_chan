import 'package:ai_chan/core/interfaces/ai_service.dart';

class GeminiAdapter implements IAIService {
  const GeminiAdapter({final String? modelId, this.runtime})
    : modelId = modelId ?? '';
  final String modelId;
  final dynamic runtime;

  dynamic get _impl {
    if (runtime != null) {
      return runtime;
    }
    // Fallback should not be used in production - DI should always provide runtime
    throw StateError(
      'GeminiAdapter runtime not provided by DI. Enhanced AI system required.',
    );
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
