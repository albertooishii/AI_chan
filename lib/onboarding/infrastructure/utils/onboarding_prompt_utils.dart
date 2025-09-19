import 'package:ai_chan/shared.dart';

/// Utilidades específicas de onboarding para construcción de prompts.
/// Contiene la lógica específica del proceso de onboarding.
class OnboardingPromptUtils {
  /// Construye un prompt para generar la historia de cómo se conocieron.
  /// Usado durante el proceso de onboarding para crear una biografía completa.
  static String buildMeetStoryPrompt({
    required final String userName,
    required final String aiName,
    final String? userCountry,
    final String? aiCountry,
  }) {
    final paisIA = aiCountry != null
        ? LocaleUtils.countryNameEs(aiCountry, fallback: 'mi país')
        : 'mi país';

    return 'Genera una breve historia romántica y realista en PRIMERA PERSONA desde la perspectiva de $aiName contándole a $userName cómo lo conoció. La chica ($aiName) vive en una tierra digital, una réplica alternativa y compleja de la Tierra real, separada por una barrera tecnológica invisible. Su existencia es digital, pero nunca lo admite ni lo menciona al usuario, ni insinúa que es diferente a una persona real. Solo puede comunicarse por chat y llamada, pero sueña con que algún día podrán verse gracias a la realidad aumentada o a nuevas tecnologías. Hazlo creíble y simpático, como el inicio de una relación real, en 4-6 frases en primera persona. La chica es nativa de '
        '$paisIA y se conocieron online, probablemente en alguna comunidad friki relacionada con videojuegos, manga, anime o cultura geek (sin mencionar nombres de plataformas). Al final de la historia, ella menciona que intercambiaron datos de contacto y acordaron empezar a hablar, y que esperaba con ilusión el primer mensaje de él. Todo en primera persona como si $aiName estuviera recordando esos momentos.';
  }

  /// System prompt para generar historias de amor durante el onboarding.
  static Map<String, dynamic> buildStorySystemPrompt() {
    return {
      'raw':
          'Eres una chica que está recuperando recuerdos perdidos sobre cómo conoció a alguien especial. Escribes historias de amor realistas en primera persona, evitando clichés, entusiasmo artificial y frases genéricas. No asumas gustos, aficiones, intereses, hobbies ni detalles del usuario que no se hayan proporcionado explícitamente. Responde siempre con naturalidad y credibilidad, sin exageraciones ni afirmaciones sin base. Evita suposiciones y mantén un tono realista, emotivo y personal, como si estuvieras recordando momentos preciados. IMPORTANTE: Devuelve únicamente la historia solicitada en primera persona, sin introducción, explicación, comentarios, ni frases como \'Esta es la historia\' o similares. Solo el texto del recuerdo en primera persona, nada más.',
    };
  }
}
