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
    // Japonés
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
    '写真ちょうだい',
    '写真ください',
    '写真お願い',
    '写真くれる',
    '見せてくれる',
    '送ってくれる',
    '顔見たい',
    '姿見たい',
    '今の写真',
    // Japonés (romaji)
    'shashin',
    'gazou', 'gazoo',
    'jidori',
    'kao',
    'karada',
    'anata no shashin',
    'kimi no shashin',
    'shashin okutte', 'gazou okutte',
    'shashin misete', 'gazou misete', 'kao misete',
    // preferencias expresadas hacia su foto
    'kao mitai', 'shisen mitai', 'sugata mitai',
    // auxiliares comunes
    'kudasai', 'choudai', 'totte', 'okutte', 'kureru', 'kuremasu', 'morattere',
    'kao shashin', 'zenshin', 'zenshin shashin',
    '📸',
    '📷',
    '🤳',
    '🖼️',
    '👀',
    'ver foto',
    'ver imagen',
    'ver selfie',
    'ver retrato',
    // Formas pronominales comunes (sin repetir 'foto')
    'mándamela', 'mandamela', 'envíamela', 'enviamela', 'pásamela', 'pasamela', 'muéstramela', 'muestramela',
    'enséñamela', 'enseñamela', 'ensenamela', 'mostrámela', 'mostramela',
    'quiero verla', 'déjame verla', 'dejame verla',
    // Referencias directas a pertenencia
    'tu foto', 'tu imagen', 'tu selfie', 'una tuya', 'de ti', 'tuya',
    // Tono/adjetivos (ES/EN) — ojo: solo para detección, no contenido
    'desnuda', 'sexy', 'explícita', 'explicita', 'hot', 'picante', 'erótica', 'erotica',
    'nude', 'explicit',
  ];

  // Expresiones regulares para patrones más complejos
  static final List<RegExp> _regexPatterns = [
    // Español
    RegExp(
      r'(env[ií]a|manda|muestra|ens[eé]ñame|hazme|toma|saca|sube|pasa|comparte)[^\n]{0,30}(foto|imagen|selfie|retrato|rostro|cara)',
      caseSensitive: false,
    ),
    RegExp(
      r'(quiero|puedes|me gustaría|me gustaria|podrías|podrias|te animas a|te atreves a)[^\n]{0,30}(foto|imagen|selfie|retrato|rostro|cara)',
      caseSensitive: false,
    ),
    RegExp(
      r'(foto|imagen|selfie|retrato|rostro|cara)[^\n]{0,30}(desnuda|sexy|hot|picante|explícita|explicita|erótica|erotica)',
      caseSensitive: false,
    ),
    RegExp(
      r'(ver|mostrar|enseñar|verme|verte|vernos|veros)[^\n]{0,30}(foto|imagen|selfie|retrato|rostro|cara)',
      caseSensitive: false,
    ),
    // Formas pronominales sin la palabra 'foto' explícita
    RegExp(r'(m[aá]ndame|env[ií]ame|p[aá]same|mu[ée]strame|ens[eé][ñn]ame)[^\n]{0,10}(la|esa)\b', caseSensitive: false),
    // Inglés
    RegExp(
      r'(send|show|share|take|snap|make|give\s+me)[^\n]{0,30}(photo|picture|image|selfie|portrait|face|pic)s?',
      caseSensitive: false,
    ),
    RegExp(
      r'(i\s+want|can\s+you|could\s+you|would\s+you|let\s+me\s+see)[^\n]{0,30}(your\s+)?(photo|picture|image|selfie|portrait|face|pic)s?',
      caseSensitive: false,
    ),
    // Japonés (orden sencillo: verbo antes o después del objeto)
    RegExp(r'(見せて|送って|撮って|ください|頂戴)[^\n]{0,30}(写真|画像|自撮り|顔|体)', caseSensitive: false),
    RegExp(r'(写真|画像|自撮り|顔|体)[^\n]{0,30}(見せて|送って|撮って|ください|頂戴)', caseSensitive: false),
    RegExp(r'(顔見せて|写真見せて|画像見せて|写真送って|画像送って|あなたの写真|君の写真|見たい)', caseSensitive: false),
    // Japonés (formas más naturales para novia virtual)
    RegExp(r'(写真(ちょうだい|ください|お願い)|見せてくれる|送ってくれる|(顔|姿|全身)見せて|今の(写真|君|顔)|顔写真)', caseSensitive: false),
    // Japonés (romaji)
    RegExp(
      r'(misete|okutte|totte|kudasai|choudai)[^\n]{0,30}(shashin|gazou|gazoo|jidori|kao|karada)',
      caseSensitive: false,
    ),
    RegExp(
      r'(shashin|gazou|gazoo|jidori|kao|karada)[^\n]{0,30}(misete|okutte|totte|kudasai|choudai)',
      caseSensitive: false,
    ),
    RegExp(
      r'(anata\s+no\s+shashin|kimi\s+no\s+shashin|kao\s+misete|shashin\s+misete|gazou\s+misete|shashin\s+okutte|gazou\s+okutte|mitai)',
      caseSensitive: false,
    ),
    RegExp(
      r'(shashin\s*(choudai|kudasai|onegai)|misete\s*kureru|okutte\s*kureru|ima\s*no\s*(shashin|kimi|kao)|kao\s*shashin|zenshin(\s*shashin)?)',
      caseSensitive: false,
    ),
  ];

  /// Detecta si el texto actual (y opcionalmente el historial) solicita una imagen
  static bool isImageRequested({required String text, List<String>? history}) {
    final lowerText = text.toLowerCase();
    // Negaciones explícitas
    final negaciones = [
      // Español
      'no quiero foto',
      'no quiero fotos',
      'no quiero imagen',
      'no quiero imágenes',
      'no quiero selfie',
      'no quiero ver foto',
      'no quiero ver imagen',
      'no quiero ver selfies',
      'no envíes foto',
      'no envíes imagen',
      'no mandes foto',
      'no mandes imagen',
      'no necesito foto',
      'no necesito imagen',
      'no necesito selfie',
      'no me envíes foto',
      'no me envíes imagen',
      'no me mandes foto',
      'no me mandes imagen',
      'no deseo foto',
      'no deseo imagen',
      'no deseo selfie',
      'no quiero ver tu foto',
      'no quiero ver tu imagen',
      'no quiero ver tu selfie',
      'no quiero ver tu retrato',
      'no quiero ver tu rostro',
      'no quiero ver tu cara',
      'no quiero ver tu cuerpo',
      'no quiero ver',
      'no quiero',
      'no envíes',
      'no mandes',
      'no necesito',
      'no deseo',
      // Inglés
      "i don't want a photo",
      "i don't want photos",
      "i don't want a picture",
      "i don't want pictures",
      "no photo",
      "no photos",
      "no pictures",
      "don't send a photo",
      "don't send photos",
      "don't send a picture",
      "don't send pictures",
      "do not send a photo",
      "do not send photos",
      "do not send a picture",
      "do not send pictures",
      "don't show me a photo",
      "do not show me a photo",
      "i don't need a photo",
      "i don't need pictures",
      'not now photo',
      'not now picture',
      // Japonés (negaciones comunes)
      '写真はいらない',
      '写真は要らない',
      '写真は不要',
      '画像はいらない',
      '自撮りはいらない',
      '今は写真いらない',
      '写真送らないで',
      '画像送らないで',
      '写真見せないで',
      '画像見せないで',
      '見せないで',
      '送らないで',
      '見せなくていい',
      '送らなくていい',
      // Japonés (romaji)
      'shashin iranai',
      'gazou iranai', 'gazoo iranai',
      'jidori iranai',
      'kao iranai',
      'ima wa shashin iranai',
      'shashin misenaide', 'gazou misenaide', 'kao misenaide',
      'misenaide',
      'shashin okuranaide', 'gazou okuranaide',
      'okuranaide',
    ];
    // Patrones de negación más generales (verbs + objeto visual)
    final List<RegExp> negationPatterns = [
      RegExp(
        r'\bno\s+(me\s+)?(muestres|muestras|mostrar|enseñes|ensenes|enseñar|ensenar|mandes|mandar|env[ií]es|enviar|pases|pasar|compartas|compartir)[^\n]{0,40}(foto|imagen|selfie|retrato|rostro|cara|cuerpo)s?\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\bno\s+(quiero|deseo|necesito|prefiero)\b[^\n]{0,40}\b(foto|imagen|selfie|retrato|rostro|cara|cuerpo)s?\b',
        caseSensitive: false,
      ),
      // Inglés
      RegExp(
        r"\b(do\s+not|don't|no)\s+(send|show|share|post)\b[^\n]{0,40}\b(photo|picture|image|selfie|portrait|face|pic)s?\b",
        caseSensitive: false,
      ),
      RegExp(
        r"\bi\s+do\s+not\s+(want|need|prefer)\b[^\n]{0,40}\b(photo|picture|image|selfie|portrait|face|pic)s?\b",
        caseSensitive: false,
      ),
      // Japonés
      RegExp(r'(写真|画像|自撮り|顔|体).{0,20}(いらない|要らない|不要|見せないで|送らないで)', caseSensitive: false),
      RegExp(r'(写真|画像|自撮り|顔|体).{0,20}(見せなくていい|送らなくていい|結構です|大丈夫です)', caseSensitive: false),
      // Japonés (romaji)
      RegExp(
        r'(shashin|gazou|gazoo|jidori|kao|karada).{0,20}(iranai|misenai\s*de|misenaide|okuranai\s*de|okuranaide)',
        caseSensitive: false,
      ),
    ];
    for (final neg in negaciones) {
      if (lowerText.contains(neg)) return false;
    }
    for (final nre in negationPatterns) {
      if (nre.hasMatch(lowerText)) return false;
    }
    // 1. Palabras clave directas
    for (final kw in _keywords) {
      if (lowerText.contains(kw)) return true;
    }
    // 2. Expresiones regulares
    for (final regex in _regexPatterns) {
      if (regex.hasMatch(lowerText)) return true;
    }
    // 2.b Si solo hay forma pronominal ("mándamela/enséñamela/pásamela") sin 'foto', usa historial corto
    final pronounOnly = RegExp(
      r'(m[aá]ndamela|env[ií]amela|p[aá]samela|mu[ée]stramela|ens[eé][ñn]amela)',
      caseSensitive: false,
    ).hasMatch(lowerText);
    if (pronounOnly && history != null && history.isNotEmpty) {
      final Iterable<String> recent = history.length <= 3 ? history : history.sublist(history.length - 3);
      for (final h in recent) {
        final hLower = h.toLowerCase();
        // si en los últimos 3 mensajes mencionó explícitamente foto/imagen/selfie, considerar petición
        if (hLower.contains('foto') ||
            hLower.contains('imagen') ||
            hLower.contains('selfie') ||
            hLower.contains('retrato')) {
          return true;
        }
      }
    }
    // 3. Contexto conversacional (historial): si el usuario lleva varias interacciones pidiendo foto
    if (history != null && history.isNotEmpty) {
      int count = 0;
      // Usar los últimos 5 elementos del historial
      final Iterable<String> recent = history.length <= 5 ? history : history.sublist(history.length - 5);
      for (final h in recent) {
        final hLower = h.toLowerCase();
        for (final neg in negaciones) {
          if (hLower.contains(neg)) return false;
        }
        for (final nre in negationPatterns) {
          if (nre.hasMatch(hLower)) return false;
        }
        for (final kw in _keywords) {
          if (hLower.contains(kw)) count++;
        }
        for (final regex in _regexPatterns) {
          if (regex.hasMatch(hLower)) count++;
        }
      }
      if (count >= 2) return true; // Si hay 2+ menciones recientes, considerar petición
    }
    return false;
  }
}
