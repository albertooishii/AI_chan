/// Servicio para detectar si el usuario está solicitando una imagen/foto en el chat
class ImageRequestService {
  // Palabras clave y emojis que suelen indicar petición de imagen (ES/EN/JA)
  static final List<String> _keywords = [
    // Español
    'foto',
    'fotito',
    'selfie',
    'selfi',
    'imagen',
    'retrato',
    'rostro',
    'cara',
    'foto tuya',
    'foto mía',
    'foto mia',
    'foto de ti',
    'foto de mí',
    'foto de mi',
    'envíame una foto',
    'mandame una foto',
    'mándame una foto',
    'quiero verte',
    'quiero una foto',
    'puedes enviarme una foto',
    'puedes mandarme una foto',
    'me enseñas una foto',
    'me mandas una foto',
    'me envías una foto',
    'muéstrame una foto',
    'muéstrame cómo eres',
    'quiero ver tu cara',
    'quiero ver cómo eres',
    'quiero ver tu cuerpo',
    'quiero ver tu rostro',
    'muestrame una imagen',
    'mándame una imagen',
    'envíame una imagen',
    // Inglés
    'photo',
    'picture',
    'pic',
    'image',
    'portrait',
    'selfie',
    'face',
    'send me a photo',
    'send me a picture',
    'show me a photo',
    'show me a picture',
    'i want a photo',
    'i want a picture',
    'let me see your face',
    'let me see you',
    'i want to see your face',
    'can you send a photo',
    'can you send me a photo',
    // Japonés (kanji/hiragana/katakana)
    '写真', // shashin (foto)
    '画像', // gazou (imagen)
    '自撮り', // jidori (selfie)
    '顔', // kao (cara)
    '体', // karada (cuerpo)
    'あなたの写真',
    '君の写真',
    '顔写真',
    '全身',
    '全身写真',
    '写メ', // sha-me (slang)
    'セルフィー', // selfie (katakana)
    '写真送って',
    '画像送って',
    '写真見せて',
    '画像見せて',
    '顔見せて',
    // Romaji
    'shashin',
    'gazou', 'gazoo',
    'jidori',
    'kao',
    'karada',
    'anata no shashin',
    'kimi no shashin',
    'shashin okutte', 'gazou okutte',
    'shashin misete', 'gazou misete', 'kao misete',
    // emojis
    '\ud83d\udcf8',
    '\ud83d\udcf7',
    '\ud83e\udd33',
    '\ud83d\uddbc\ufe0f',
    '\ud83d\udc40',
  ];

  static final List<RegExp> _regexPatterns = [
    RegExp(
      r'(env[ií]a|manda|muestra|ens[eé]ñame|hazme|toma|saca|sube|pasa|comparte)[^\n]{0,30}(foto|imagen|selfie|retrato|rostro|cara)',
      caseSensitive: false,
    ),
    RegExp(
      r'(quiero|puedes|me gustar[ií]a|me gustaria|podr[ií]as|podrias|te animas a|te atreves a)[^\n]{0,30}(foto|imagen|selfie|retrato|rostro|cara)',
      caseSensitive: false,
    ),
  ];

  /// Detecta si el texto actual (y opcionalmente el historial) solicita una imagen.
  ///
  /// Mejoras principales:
  /// - Si `lastAssistantHadImage==true` y el usuario no pide explícitamente otra foto, NO se considera
  ///   solicitud (evita falsos positivos cuando el usuario responde a una foto ya enviada).
  /// - Añade patrones negativos (p. ej. "no quiero foto") y reglas para evitar falsos positivos en textos
  ///   muy cortos o ambiguos.
  static bool isImageRequested({required String text, List<String>? history, bool? lastAssistantHadImage}) {
    final lowerText = text.toLowerCase().trim();
    if (lowerText.isEmpty) return false;

    // Patrones que claramente niegan una petición de foto
    final List<RegExp> negativePatterns = [
      RegExp(r'\bno quiero (foto|imagen)\b', caseSensitive: false),
      RegExp(r'\bno me (mandes|env[íi]es) (foto|imagen)\b', caseSensitive: false),
      RegExp(r'\bno necesito (foto|imagen)\b', caseSensitive: false),
      RegExp(r'\bno quiero ver\b', caseSensitive: false),
    ];
    for (final np in negativePatterns) {
      if (np.hasMatch(lowerText)) return false;
    }

    // Patrones que indican petición explícita (verbo cercano a 'foto')
    final explicitRequestRegex = RegExp(
      r'(?:env[ií]a|manda|muestra|ens[eé]ñame|hazme|saca|mu[eé]strame|puedes|podr[ií]as|quiero|me gustar[ií]a|me gustaria|me mandas|me env[ií]as)[^\n]{0,60}(foto|imagen|selfie|retrato|foto tuya|otra foto|otra imagen|otra)',
      caseSensitive: false,
    );
    if (explicitRequestRegex.hasMatch(lowerText)) return true;

    // Peticiones explícitas de "otra foto/otra imagen" o variaciones cortas
    if (lowerText.contains('otra foto') ||
        lowerText.contains('otra imagen') ||
        RegExp(r'\botra\b').hasMatch(lowerText) && RegExp(r'foto|imagen').hasMatch(lowerText)) {
      return true;
    }

    // Si la IA acaba de enviar una foto y el usuario no pide explícitamente otra, NO contar como petición.
    if (lastAssistantHadImage == true) {
      // Considerar algunas frases explícitas que sí piden otra foto
      final explicitAgain = RegExp(
        r'(otra|otra vez|otra m[ií]a|otra similar|otra, por favor|otra por favor|otra\?)',
        caseSensitive: false,
      );
      if (explicitAgain.hasMatch(lowerText)) return true;
      // Caso: el usuario pide un tipo de foto diferente (ej: 'una de cuerpo entero', 'una más sexy')
      final differentType = RegExp(
        r'(cuerpo entero|full body|medio cuerpo|primer plano|close[- ]?up|más sexy|más natural)',
        caseSensitive: false,
      );
      if (differentType.hasMatch(lowerText)) return true;
      return false;
    }

    // Evitar falsos positivos en palabras ambiguas si el texto es muy corto
    final ambiguousShortWords = {'cara', 'rostro', 'retrato', 'imagen', 'foto', 'selfie'};
    for (final kw in _keywords) {
      if (lowerText.contains(kw)) {
        // Si la keyword es una de las ambiguas y el texto es corto (<=12 caracteres), ignorar
        if (ambiguousShortWords.contains(kw) && lowerText.length <= 12) return false;
        return true;
      }
    }

    // Revisar patrones regex existentes (más flexibles)
    for (final regex in _regexPatterns) {
      if (regex.hasMatch(lowerText)) return true;
    }

    // Revisar historial reciente: si el usuario ya pidió foto en los últimos 3 mensajes
    if (history != null && history.isNotEmpty) {
      final recent = history.length <= 3 ? history : history.sublist(history.length - 3);
      for (final h in recent) {
        final hLower = h.toLowerCase();
        // Solo considerar entradas del usuario anteriores (si la lista mezcla remitentes, asumimos que son textos puros)
        for (final kw in _keywords) {
          if (hLower.contains(kw)) return true;
        }
      }
    }

    return false;
  }
}
