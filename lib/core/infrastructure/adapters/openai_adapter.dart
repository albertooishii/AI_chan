import 'package:ai_chan/shared/services/ai_runtime_provider.dart'
    as runtime_factory;
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';

/// Thin adapter that implements the legacy IAIService port and delegates to
/// the runtime instance created by runtime_factory. This keeps DI stable
/// while allowing runtimes to be created centrally.
class OpenAIAdapter implements IAIService {
  final String modelId;
  final dynamic runtime;

  /// Optional [runtime] allows tests or the DI layer to inject a concrete
  /// runtime instance (OpenAIService) instead of relying on the internal
  /// factory. If not provided, the adapter falls back to the centralized
  /// runtime factory.
  OpenAIAdapter({String? modelId, this.runtime})
    : modelId = modelId ?? Config.getDefaultTextModel();

  dynamic get _impl {
    final resolved = (runtime != null)
        ? (runtime)
        : runtime_factory.getRuntimeAIServiceForModel(
            modelId.isNotEmpty ? modelId : Config.getDefaultTextModel(),
          );
    return resolved;
  }

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
    } catch (e) {
      return {'text': ''};
    }
  }

  @override
  Future<String?> textToSpeech(
    String text, {
    String voice = '',
    Map<String, dynamic>? options,
  }) async {
    try {
      // Extraer opciones adicionales para OpenAI TTS
      final model = options?['model'] as String?;
      final speed = options?['speed'] as double? ?? 1.0;
      final instructions = options?['instructions'] as String?;

      // Llamar al método textToSpeech con todas las opciones
      final file = await _impl.textToSpeech(
        text: text,
        voice: voice,
        model: model,
        speed: speed,
        instructions: instructions,
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }
}
