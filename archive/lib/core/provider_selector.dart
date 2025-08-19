import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;
import 'package:ai_chan/services/ai_service.dart' as runtime_ai;

/// Selector que usa `Config` para decidir el runtime por defecto y delega
/// la creación al `runtime_factory`. Esto evita instanciaciones directas
/// fuera de la fábrica central.
runtime_ai.AIService getRuntimeForDefaultModel() {
  final model = Config.getDefaultTextModel().trim().toLowerCase();
  if (model.isEmpty) return runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash');
  return runtime_factory.getRuntimeAIServiceForModel(model);
}

/// Variante que acepta un modelId explícito (útil en llamadas directas).
runtime_ai.AIService getRuntimeForModel(String modelId) {
  final model = modelId.trim().toLowerCase();
  if (model.isEmpty) return getRuntimeForDefaultModel();
  return runtime_factory.getRuntimeAIServiceForModel(model);
}
