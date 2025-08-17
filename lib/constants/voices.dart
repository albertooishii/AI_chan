/// Lista centralizada de voces TTS permitidas por la API.
/// Mantener sincronizada con validación del backend.
const List<String> kAvailableVoices = ['nova', 'shimmer', 'echo', 'onyx', 'fable', 'alloy', 'ash', 'sage', 'coral'];

/// Obtiene la voz por defecto efectiva dado el valor opcional de entorno (OPENAI_VOICE).
/// Si OPENAI_VOICE no está o es inválida, retorna el primer elemento permitido.
String resolveDefaultVoice(String? envVoice) {
  if (envVoice != null && kAvailableVoices.contains(envVoice)) return envVoice;
  return kAvailableVoices.first; // 'nova'
}
