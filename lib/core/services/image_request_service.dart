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

  /// Detecta si el texto actual (y opcionalmente el historial) solicita una imagen
  static bool isImageRequested({required String text, List<String>? history}) {
    final lowerText = text.toLowerCase();
    for (final kw in _keywords) {
      if (lowerText.contains(kw)) return true;
    }
    for (final regex in _regexPatterns) {
      if (regex.hasMatch(lowerText)) return true;
    }
    if (history != null && history.isNotEmpty) {
      final recent = history.length <= 3 ? history : history.sublist(history.length - 3);
      for (final h in recent) {
        final hLower = h.toLowerCase();
        for (final kw in _keywords) {
          if (hLower.contains(kw)) return true;
        }
      }
    }
    return false;
  }
}
