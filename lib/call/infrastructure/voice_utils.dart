import 'package:ai_chan/call/infrastructure/adapters/openai_speech_service.dart';

/// Pequeña fachada para exponer la funcionalidad de obtención de voces
/// desde la capa de infraestructura sin que la capa de presentación importe
/// directamente adaptadores internos.
Future<List<Map<String, dynamic>>> getOpenAIVoices({
  final bool forceRefresh = false,
  final bool femaleOnly = false,
}) {
  return OpenAISpeechService.fetchOpenAIVoices(
    forceRefresh: forceRefresh,
    femaleOnly: femaleOnly,
  );
}
