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
    'eu-ES': 'Euskera (España)',
    'ca-ES': 'Catalán (España)',
    'gl-ES': 'Gallego (España)',
    'oc-ES': 'Occitano (España)',
  };

  /// Convierte géneros a nombres legibles
  static final Map<String, String> _genderNames = {
    'MALE': 'Masculina',
    'FEMALE': 'Femenina',
    'NEUTRAL': 'Neutral',
  };

  /// Devuelve el nombre real tal como lo proporciona la API.
  /// Prioridad: `displayName` / `display_name` (si existe) -> `name`.
  /// NO recorta ni elimina partes del nombre: se presenta exactamente como viene.
  static String getGoogleVoiceFriendlyName(final Map<String, dynamic> voice) {
    final display =
        voice['displayName'] as String? ??
        voice['display_name'] as String? ??
        voice['name'] as String? ??
        '';
    if (display.isEmpty) return 'Voz sin nombre';
    return display;
  }

  /// Normaliza un código de idioma como 'es_es' o 'es-es' a la forma
  /// 'es-ES' cuando sea posible. Si la entrada no tiene región, devuelve
  /// la parte de idioma en minúsculas ('es').
  static String _normalizeLangCode(final String code) {
    if (code.trim().isEmpty) return code;
    final cleaned = code.replaceAll('_', '-').trim();
    final parts = cleaned.split('-');
    if (parts.length == 1) return parts[0].toLowerCase();
    final lang = parts[0].toLowerCase();
    final region = parts[1].toUpperCase();
    return '$lang-$region';
  }

  // ...existing code...

  /// Genera información de subtítulo para mostrar en la UI
  static String getVoiceSubtitle(final Map<String, dynamic> voice) {
    final gender = voice['ssmlGender'] as String? ?? '';
    final languageCodes =
        (voice['languageCodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final name = voice['name'] as String? ?? '';

    final genderName = _genderNames[gender] ?? gender;

    // Determinar nombre de idioma preferido
    String languageName = '';
    if (languageCodes.isNotEmpty) {
      final cand = _normalizeLangCode(languageCodes.first);
      languageName =
          _languageNames[cand] ??
          _languageNames[languageCodes.first] ??
          languageCodes.first;
    } else {
      // intentar extraer de 'name' formato 'xx-YY-...'
      final parts = name.split('-');
      if (parts.length >= 2) {
        final code = _normalizeLangCode('${parts[0]}-${parts[1]}');
        languageName = _languageNames[code] ?? code;
      }
    }

    // Detectar tipo de voz: preferir 'Neural' si aparece
    String voiceType = '';
    final lower = name.toLowerCase();
    if (lower.contains('neural')) {
      voiceType = 'Neural';
    } else if (lower.contains('wavenet')) {
      voiceType = 'WaveNet';
    } else if (lower.contains('standard')) {
      voiceType = 'Estándar';
    }

    // Construir partes y unir con ' · '
    final parts = <String>[];
    if (genderName.isNotEmpty) parts.add(genderName);
    if (languageName.isNotEmpty) parts.add(languageName);
    if (voiceType.isNotEmpty) parts.add(voiceType);

    return parts.join(' · ');
  }
}
