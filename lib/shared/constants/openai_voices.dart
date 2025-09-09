/// Mapa de género por token de voz. Las etiquetas están en español y pueden
/// usarse para mostrar "Masculina" / "Femenina" en la UI.
/// Mantener sincronizado con cualquier lugar que consuma estos tokens.
/// Actualizado para incluir las nuevas voces Cedar y Marin del modelo gpt-realtime.
const Map<String, String> kOpenAIVoiceGender = {
  'sage': 'Femenina',
  'alloy': 'Femenina',
  'ash': 'Masculina',
  'ballad': 'Femenina',
  'coral': 'Femenina',
  'echo': 'Masculina',
  'fable': 'Femenina',
  'onyx': 'Masculina',
  'nova': 'Femenina',
  'shimmer': 'Femenina',
  'verse': 'Masculina',
  'cedar': 'Masculina',
  'marin': 'Femenina',
};

/// Lista derivada (en tiempo de compilación se construye a partir de las claves
/// del mapa). Usar `kOpenAIVoiceGender.keys.toList()` en código nuevo y preferir
/// `kOpenAIVoiceGender` como fuente de verdad.
List<String> get kOpenAIVoices => kOpenAIVoiceGender.keys.toList();

/// Devuelve la voz por defecto efectiva dado el valor opcional de entorno
/// (OPENAI_VOICE_NAME). Si el valor no está o es inválido, retorna 'marin' si
/// existe en el mapa, o la primera clave disponible.
String resolveDefaultVoice(final String? envVoice) {
  final keys = kOpenAIVoices;
  if (envVoice != null && keys.contains(envVoice)) return envVoice;
  if (keys.contains('marin')) return 'marin';
  return keys.isNotEmpty ? keys.first : 'marin';
}
