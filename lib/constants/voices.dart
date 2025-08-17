/// Lista centralizada de voces TTS permitidas por la API.
/// Mantener sincronizada con validación del backend.
/// Nota: En realtime actualmente NO están disponibles 'nova', 'ash', 'coral'; usamos 'sage' como común a ambos endpoints.
const List<String> kOpenAIVoices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];

/// Voces femeninas de OpenAI
const List<String> kOpenAIFemaleVoices = ['nova', 'shimmer'];

/// Lista básica de voces de Google (se complementa dinámicamente con fetchGoogleVoices)
const List<String> kGoogleVoices = [
  'es-ES-Standard-A',
  'es-ES-Standard-B',
  'es-ES-Standard-C',
  'es-ES-Standard-D',
  'en-US-Standard-B',
  'en-US-Standard-C',
  'en-US-Standard-D',
  'en-US-Standard-E',
];

/// Obtiene la voz por defecto efectiva dado el valor opcional de entorno (OPENAI_VOICE).
/// Si OPENAI_VOICE no está o es inválida, retorna el primer elemento permitido.
String resolveDefaultVoice(String? envVoice) {
  if (envVoice != null && kOpenAIVoices.contains(envVoice)) return envVoice;
  return kOpenAIVoices.first; // 'sage'
}

List<String> getAvailableVoices(String provider) {
  switch (provider.toLowerCase()) {
    case 'openai':
      return kOpenAIVoices;
    case 'google':
      return kGoogleVoices;
    default:
      return kOpenAIVoices;
  }
}
