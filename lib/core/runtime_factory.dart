import '../shared/services/gemini_service.dart';
import '../shared/services/openai_service.dart';
import '../shared/services/ai_service.dart' as runtime_ai;
import 'package:ai_chan/core/config.dart';

/// Fábrica centralizada para obtener instancias runtime de AI (OpenAI/Gemini).
/// Mantiene singletons por modelo.
final Map<String, runtime_ai.AIService> _runtimeAiSingletons = {};

runtime_ai.AIService getRuntimeAIServiceForModel(String modelId) {
  final normalized = modelId.trim().toLowerCase();
  final defaultModel = Config.getDefaultTextModel().trim().toLowerCase();
  final key = normalized.isEmpty
      ? (defaultModel.isEmpty ? 'default' : defaultModel)
      : normalized;
  if (_runtimeAiSingletons.containsKey(key)) return _runtimeAiSingletons[key]!;

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
