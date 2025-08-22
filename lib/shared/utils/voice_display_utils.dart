/// Utilidades para mostrar nombres de voces de forma más amigable
class VoiceDisplayUtils {
  /// Convierte códigos de idioma a nombres legibles
  static final Map<String, String> _languageNames = {
    'es-ES': 'Español (España)',
    'es-US': 'Español (Estados Unidos)',
    'es-MX': 'Español (México)',
    'es-AR': 'Español (Argentina)',
    'es-CO': 'Español (Colombia)',
    'es-CL': 'Español (Chile)',
    'es-PE': 'Español (Perú)',
    'es-VE': 'Español (Venezuela)',
    'en-US': 'Inglés (Estados Unidos)',
    'en-GB': 'Inglés (Reino Unido)',
    'en-AU': 'Inglés (Australia)',
    'en-CA': 'Inglés (Canadá)',
    'fr-FR': 'Francés (Francia)',
    'fr-CA': 'Francés (Canadá)',
    'de-DE': 'Alemán (Alemania)',
    'it-IT': 'Italiano (Italia)',
    'pt-BR': 'Portugués (Brasil)',
    'pt-PT': 'Portugués (Portugal)',
    'ja-JP': 'Japonés (Japón)',
    'ko-KR': 'Coreano (Corea del Sur)',
    'zh-CN': 'Chino Mandarín (China)',
    'zh-TW': 'Chino Tradicional (Taiwán)',
    'ru-RU': 'Ruso (Rusia)',
    'ar-XA': 'Árabe',
    'hi-IN': 'Hindi (India)',
    'th-TH': 'Tailandés (Tailandia)',
    'vi-VN': 'Vietnamita (Vietnam)',
    'tr-TR': 'Turco (Turquía)',
    'pl-PL': 'Polaco (Polonia)',
    'nl-NL': 'Holandés (Países Bajos)',
    'sv-SE': 'Sueco (Suecia)',
    'da-DK': 'Danés (Dinamarca)',
    'nb-NO': 'Noruego (Noruega)',
    'fi-FI': 'Finlandés (Finlandia)',
    'uk-UA': 'Ucraniano (Ucrania)',
    'cs-CZ': 'Checo (República Checa)',
    'sk-SK': 'Eslovaco (Eslovaquia)',
    'hu-HU': 'Húngaro (Hungría)',
    'ro-RO': 'Rumano (Rumania)',
    'bg-BG': 'Búlgaro (Bulgaria)',
    'hr-HR': 'Croata (Croacia)',
    'sr-RS': 'Serbio (Serbia)',
    'sl-SI': 'Esloveno (Eslovenia)',
    'et-EE': 'Estonio (Estonia)',
    'lv-LV': 'Letón (Letonia)',
    'lt-LT': 'Lituano (Lituania)',
    'mt-MT': 'Maltés (Malta)',
    'eu-ES': 'Euskera (País Vasco)',
    'ca-ES': 'Catalán (Cataluña)',
    'gl-ES': 'Gallego (Galicia)',
  };

  /// Convierte géneros a nombres legibles
  static final Map<String, String> _genderNames = {'MALE': 'Masculina', 'FEMALE': 'Femenina', 'NEUTRAL': 'Neutral'};

  /// Genera un nombre amigable para una voz de Google TTS
  /// Ejemplo: 'es-ES-Neural2-A' -> 'Elena (Neural)'
  static String getGoogleVoiceFriendlyName(Map<String, dynamic> voice) {
    final name = voice['name'] as String? ?? '';
    final gender = voice['ssmlGender'] as String? ?? '';

    // Debug logs removed to reduce console noise in normal runs.

    if (name.isEmpty) return 'Voz sin nombre';

    // Extraer información del nombre técnico
    final parts = name.split('-');
    // parts parsed
    if (parts.length < 2) return name; // Si no sigue el formato esperado, devolver como está

    final langCode = '${parts[0]}-${parts[1]}'; // ej: 'es-ES'

    // Determinar tipo de voz
    String voiceType = '';
    String voiceId = '';

    if (parts.length >= 3) {
      final thirdPart = parts[2];
      // third part parsed

      if (thirdPart.toLowerCase().startsWith('neural')) {
        voiceType = 'Neural';
        if (parts.length >= 4) {
          voiceId = parts[3]; // ej: 'A', 'B', 'C'
        }
        // detected neural
      } else if (thirdPart.toLowerCase().startsWith('standard')) {
        voiceType = 'Estándar';
        if (parts.length >= 4) {
          voiceId = parts[3];
        }
        // detected standard
      } else if (thirdPart.toLowerCase().startsWith('wavenet')) {
        voiceType = 'WaveNet';
        if (parts.length >= 4) {
          voiceId = parts[3];
        }
        // detected wavenet
      } else {
        voiceId = thirdPart;
        // unknown type
      }
    }

    // Generar nombres más amigables basados en el patrón común
    String friendlyName = _generateFriendlyName(langCode, gender, voiceId);
    // friendly name generated

    // Construir el nombre final
    String displayName = friendlyName;

    // Añadir tipo de voz si es relevante
    if (voiceType.isNotEmpty) {
      displayName += ' ($voiceType)';
    }

    return displayName;
  }

  /// Genera nombres amigables basados en patrones comunes
  static String _generateFriendlyName(String langCode, String gender, String voiceId) {
    // Para voces de Google, usar el nombre técnico directamente
    // No inventamos nombres, usamos la nomenclatura oficial
    final genderName = _genderNames[gender] ?? gender;

    if (voiceId.isNotEmpty) {
      return '$genderName $voiceId';
    }

    final languageName = _languageNames[langCode] ?? langCode;
    return '$languageName $genderName';
  }

  /// Obtiene el nombre técnico original de la voz (para usar en la API)
  static String getVoiceTechnicalName(Map<String, dynamic> voice) {
    return voice['name'] as String? ?? '';
  }

  /// Genera información de subtítulo para mostrar en la UI
  static String getVoiceSubtitle(Map<String, dynamic> voice) {
    final gender = voice['ssmlGender'] as String? ?? '';
    final languageCodes = (voice['languageCodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final name = voice['name'] as String? ?? '';

    // Debug: imprimir el nombre real de la voz para diagnosis
    // Removed debug prints to reduce runtime noise

    final genderName = _genderNames[gender] ?? gender;
    final langs = languageCodes.map((lang) => _languageNames[lang] ?? lang).join(', ');

    // Detectar tipo de voz con prioridad: WaveNet > Neural > Standard
    String voiceType = '';
    if (name.toLowerCase().contains('wavenet')) {
      voiceType = ' (WaveNet)'; // La tecnología más avanzada
      // detected wavenet
    } else if (name.toLowerCase().contains('neural')) {
      voiceType = ' (Neural)'; // Tecnología neural general (incluye Neural2)
      // detected neural
    } else if (name.toLowerCase().contains('standard')) {
      voiceType = ' (Estándar)'; // Voces tradicionales
      // detected standard
    } else {
      // unknown
    }

    String subtitle = genderName + voiceType;
    if (langs.isNotEmpty) {
      subtitle += ' - $langs';
    }

    // result ready
    return subtitle;
  }
}
