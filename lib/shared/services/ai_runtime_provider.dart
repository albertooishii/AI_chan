import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/services/gemini_service.dart';
import 'package:ai_chan/shared/services/openai_service.dart';
import 'package:ai_chan/shared/services/ai_service.dart' as runtime_ai;
import 'package:ai_chan/core/config.dart';

/// Fábrica centralizada para obtener instancias runtime de AI (OpenAI/Gemini).
/// Mantiene singletons por modelo.
final Map<String, runtime_ai.AIService> _runtimeAiSingletons = {};

runtime_ai.AIService getRuntimeAIServiceForModel(String modelId) {
  final normalized = modelId.trim().toLowerCase();
  final defaultModel = Config.getDefaultTextModel().trim().toLowerCase();
  final key = normalized.isEmpty ? (defaultModel.isEmpty ? 'default' : defaultModel) : normalized;
  if (_runtimeAiSingletons.containsKey(key)) {
    final existing = _runtimeAiSingletons[key]!;
    // Sanity check: if the cached singleton type doesn't match the model prefix, replace it
    if (key.startsWith('gpt-') && existing.runtimeType.toString() != 'OpenAIService') {
      Log.w('[ai_runtime_provider] Warning: singleton type mismatch for $key (expected OpenAIService). Recreating.');
      final implNew = OpenAIService();
      _runtimeAiSingletons[key] = implNew;
      return implNew;
    }
    if ((key.startsWith('gemini-') || key.startsWith('imagen-')) &&
        existing.runtimeType.toString() != 'GeminiService') {
      Log.w('[ai_runtime_provider] Warning: singleton type mismatch for $key (expected GeminiService). Recreating.');
      final implNew = GeminiService();
      _runtimeAiSingletons[key] = implNew;
      return implNew;
    }
    return existing;
  }

  runtime_ai.AIService impl;
  if (key.startsWith('gpt-')) {
    impl = OpenAIService();
  } else if (key.startsWith('gemini-') || key.startsWith('imagen-')) {
    impl = GeminiService();
  } else if (key == 'default') {
    // fallback preferido: Gemini
    impl = GeminiService();
  } else {
    // Unknown prefix: default to OpenAI for text models
    impl = OpenAIService();
  }
  _runtimeAiSingletons[key] = impl;
  return impl;
}

/// Devuelve el modelId por defecto configurado en `Config`.
String getDefaultModelId() => Config.getDefaultTextModel();
