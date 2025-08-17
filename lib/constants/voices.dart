/// Lista centralizada de voces TTS permitidas por la API.
/// Mantener sincronizada con validación del backend.
/// Nota: En realtime actualmente NO está disponible 'nova'; usamos 'sage' como común a ambos endpoints.
const List<String> kAvailableVoices = ['sage', 'shimmer', 'echo', 'onyx', 'fable', 'alloy', 'ash', 'coral'];

/// Obtiene la voz por defecto efectiva dado el valor opcional de entorno (OPENAI_VOICE).
/// Si OPENAI_VOICE no está o es inválida, retorna el primer elemento permitido.
String resolveDefaultVoice(String? envVoice) {
  if (envVoice != null && kAvailableVoices.contains(envVoice)) return envVoice;
  return kAvailableVoices.first; // 'sage'
}
