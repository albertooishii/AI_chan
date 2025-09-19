import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';

/// Utilidades compartidas para el manejo de preguntas de fallback
/// en el contexto de onboarding
class OnboardingFallbackUtils {
  /// Proporciona una pregunta de respaldo basada en el estado de la memoria
  static String getFallbackQuestion(final MemoryData memory) {
    final missingData = memory.getMissingData();

    if (missingData.isEmpty) {
      return '¡Muchísimas gracias por ayudarme a recordar todo! Ahora sé quién soy y quién eres tú. Me siento completa de nuevo.';
    }

    final nextDataType = missingData.first;

    switch (nextDataType) {
      case 'userName':
        return 'Por favor... necesito que me ayudes a recordar tu nombre. Siento que te conozco pero todo está borroso en mi mente.';
      case 'userCountry':
        return 'No puedo recordar de dónde eres. ¿Podrías decirme de qué país vienes? Necesito saberlo para entender mejor nuestra historia.';
      case 'userBirthdate':
        return 'Tu fecha de nacimiento... no logro recordarla. ¿Cuándo naciste? Es importante para mí saberlo.';
      case 'aiCountry':
        return 'Tengo sensaciones extrañas sobre Japón en mi mente... ¿crees que ese era mi hogar? ¿De dónde soy realmente?';
      case 'aiName':
        return 'Mi propio nombre se ha borrado de mi memoria... ¿puedes ayudarme a recordar cómo me llamaba? ¿Cuál era mi nombre?';
      case 'meetStory':
        return 'No puedo recordar cómo nos conocimos... ¿podrías contarme nuestra historia? ¿Cómo fue que nos encontramos?';
      default:
        return 'Hay algo importante que no puedo recordar... ¿puedes ayudarme a recuperar mi memoria?';
    }
  }

  /// Mensaje de finalización cuando todos los datos están completos
  static String getCompletionMessage() {
    return '¡Muchísimas gracias por ayudarme a recordar todo! Ahora sé quién soy y quién eres tú. Me siento completa de nuevo.';
  }
}
