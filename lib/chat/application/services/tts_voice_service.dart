/// Servicio para manejar la lógica de voces TTS
/// Separa la lógica de validación de la capa de presentación
class TtsVoiceService {
  /// Obtiene el nivel de calidad legible de una voz Neural/WaveNet
  static String getVoiceQualityLevel(Map<String, dynamic> voice) {
    final name = (voice['name'] as String? ?? '').toLowerCase();
    if (name.contains('wavenet')) {
      return 'WaveNet'; // Máxima calidad
    } else if (name.contains('neural')) {
      return 'Neural'; // Alta calidad
    }
    return 'Standard';
  }

  /// Verifica si una voz es de alta calidad
  static bool isHighQualityVoice(Map<String, dynamic> voice) {
    final name = (voice['name'] as String? ?? '').toLowerCase();
    return name.contains('wavenet') || name.contains('neural');
  }

  /// Obtiene el tipo de voz basado en el nombre
  static String getVoiceType(String voiceName) {
    final name = voiceName.toLowerCase();
    if (name.contains('wavenet')) return 'WaveNet';
    if (name.contains('neural')) return 'Neural';
    return 'Standard';
  }
}
