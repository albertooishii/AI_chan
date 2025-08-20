/// Lista centralizada de voces TTS permitidas por la API.
/// Mantener sincronizada con validación del backend.
/// Nota: En realtime actualmente NO están disponibles 'nova', 'ash', 'coral'; usamos 'sage' como común a ambos endpoints.
/// IMPORTANTE: El primer elemento se utiliza como fallback por defecto (resolveDefaultVoice) si la voz de entorno es inválida.
const List<String> kOpenAIVoices = [
  'sage', // voz base por compatibilidad realtime + TTS
  'alloy',
  'echo',
  'fable',
  'onyx',
  'nova',
  'shimmer',
];

/// Voces femeninas de OpenAI (incluimos 'sage' si se desea permitir selección neutral/femenina)
const List<String> kOpenAIFemaleVoices = ['sage', 'nova', 'shimmer'];

// Nota sobre Google TTS: Ya no mantenemos una lista estática aquí; ahora se obtienen
// dinámicamente mediante GoogleSpeechService.fetchGoogleVoices() con caché local.
// Mantener esta sección sin lista evita desincronizaciones.

/// Obtiene la voz por defecto efectiva dado el valor opcional de entorno (OPENAI_VOICE).
/// Si OPENAI_VOICE no está o es inválida, retorna el primer elemento permitido.
String resolveDefaultVoice(String? envVoice) {
  if (envVoice != null && kOpenAIVoices.contains(envVoice)) return envVoice;
  return kOpenAIVoices.first; // 'sage'
}

// getAvailableVoices(String provider) eliminado: se usaba sólo para listas estáticas.
// Para OpenAI usar kOpenAIVoices directamente; para Google usar GoogleSpeechService.fetchGoogleVoices().
