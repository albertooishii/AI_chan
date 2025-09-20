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
}
