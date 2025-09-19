/// Servicio para manejar la lógica de voces TTS
/// Separa la lógica de validación de la capa de presentación
class TtsVoiceService {
  /// Obtiene el nivel de calidad legible de una voz Neural/WaveNet/Polyglot
  static String getVoiceQualityLevel(final Map<String, dynamic> voice) {
    final voiceName = voice['name'] as String? ?? '';
    final naturalSampleRateHertz = voice['naturalSampleRateHertz'] as int? ?? 0;

    // Determine quality based on voice name patterns (case insensitive)
    if (voiceName.contains('WaveNet')) {
      return 'WaveNet';
    } else if (voiceName.contains('Neural2')) {
      return 'Neural2';
    } else if (voiceName.contains('Polyglot')) {
      return 'Polyglot';
    } else if (voiceName.contains('Journey')) {
      return 'Journey';
    } else if (voiceName.contains('Studio')) {
      return 'Studio';
    } else if (voiceName.contains('Neural')) {
      return 'Neural';
    } else if (voiceName.contains('Standard')) {
      return 'Standard';
    } else if (naturalSampleRateHertz >= 24000) {
      return 'High Quality';
    } else {
      return 'Standard';
    }
  }

  /// Verifica si una voz es de alta calidad
  static bool isHighQualityVoice(final Map<String, dynamic> voice) {
    final quality = getVoiceQualityLevel(voice);
    return quality == 'WaveNet' ||
        quality == 'Neural2' ||
        quality == 'Polyglot' ||
        quality == 'Journey' ||
        quality == 'Studio' ||
        quality == 'Neural' ||
        quality == 'High Quality';
  }

  /// Obtiene el tipo de voz basado en el nombre
  static String getVoiceType(final String voiceName) {
    return getVoiceQualityLevel({'name': voiceName});
  }
}
