import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ImageRequestResult {
  final bool detected;
  final String reason;
  final String matchedPhrase;
  final int score; // 0..100

  ImageRequestResult({required this.detected, this.reason = '', this.matchedPhrase = '', this.score = 0});

  @override
  String toString() =>
      'ImageRequestResult(detected: $detected, reason: $reason, matched: "$matchedPhrase", score: $score)';
}

class ImageRequestService {
  static final List<String> _highConfidenceKeywords = [
    'envíame una foto',
    'enviame una foto',
    'mándame una foto',
    'mandame una foto',
    'envíame una selfie',
    'enviame una selfie',
    'mándame una selfie',
    'mandame una selfie',
    'envíame un selfie',
    'enviame un selfie',
    'mándame un selfie',
    'mandame un selfie',
    'envíame foto',
    'enviame foto',
    'envíame una imagen',
    'enviame una imagen',
    'mándame una imagen',
    'mandame una imagen',
    'quiero verte',
    'quiero una foto',
    'quiero ver tu cara',
    'ahora mismo te la mando',
    'ahora mismo te la envio',
    'ahora te la mando',
    'la hago ahora',
    'te la mando ahora',
    'mándame un selfie',
    'mandame un selfie',
    'mándame una selfie',
    'mandame una selfie',
    'mándame una fotito',
    'mandame una fotito',
    'mándame una fotito',
    'mandame una fotito',
    'mándame una fotito',
    'send me a photo',
    'send me a picture',
    'show me a photo',
  ];

  static final List<String> _keywords = [
    'foto',
    'fotito',
    'selfie',
    'selfi',
    'imagen',
    'retrato',
    'rostro',
    'cara',
    'picture',
    'photo',
  ];

  static final List<RegExp> _explicitRegex = [
    RegExp(
      r"\b(env[ií]a|manda|muestr|ens[eé]ñ|ens[eé]ñame|hazme|saca|mu[eé]strame|m[áa]ndame|por favor)[^\n]{0,40}\b(foto|imagen|selfie|retrato|una foto|una imagen)\b",
      caseSensitive: false,
    ),
    RegExp(
      r"\b(quiero|puedes|podr[ií]as?|me gustar[ií]a|me gustaria|me mandas|me env[ií]as)[^\n]{0,40}\b(foto|imagen|selfie|retrato|una foto)\b",
      caseSensitive: false,
    ),
    RegExp(r"\b(send|show|can you send|can you show)[^\n]{0,40}\b(photo|picture)\b", caseSensitive: false),
  ];

  static final List<RegExp> _negativePatterns = [
    RegExp(r"\b(no quiero (foto|imagen))\b", caseSensitive: false),
    RegExp(r"\b(no me (mandes|env[ií]es) (foto|imagen))\b", caseSensitive: false),
    RegExp(r"\b(no necesito (foto|imagen))\b", caseSensitive: false),
  ];

  static final RegExp _anotherPhotoRegex = RegExp(
    r"\b(otra foto|otra imagen|otra vez|otra similar|otra, por favor|otra por favor)\b",
    caseSensitive: false,
  );
  static final RegExp _typeRequestRegex = RegExp(
    r"\b(cuerpo entero|full body|medio cuerpo|primer plano|close[- ]?up|más sexy|más natural|más grande)\b",
    caseSensitive: false,
  );

  // Nota: antes usábamos una regex explícita para ack/followups; en su lugar
  // usamos una heurística flexible que evalúa si el mensaje del usuario es
  // corto/poco informativo (un followup) y si hay una promesa pendiente del
  // asistente en el historial reciente.

  static ImageRequestResult detectImageRequest({required String text, List<Message>? history}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return ImageRequestResult(detected: false, reason: 'empty', matchedPhrase: '', score: 0);
    final lower = trimmed.toLowerCase();

    for (final neg in _negativePatterns) {
      final m = neg.firstMatch(lower);
      if (m != null) {
        return ImageRequestResult(detected: false, reason: 'negative_match', matchedPhrase: m.group(0) ?? '', score: 0);
      }
    }

    for (final p in _highConfidenceKeywords) {
      if (lower.contains(p)) {
        return ImageRequestResult(detected: true, reason: 'high_confidence_phrase', matchedPhrase: p, score: 95);
      }
    }

    for (final rx in _explicitRegex) {
      final m = rx.firstMatch(lower);
      if (m != null) {
        return ImageRequestResult(
          detected: true,
          reason: 'explicit_verb_regex',
          matchedPhrase: m.group(0) ?? '',
          score: 90,
        );
      }
    }

    final mAnother = _anotherPhotoRegex.firstMatch(lower);
    if (mAnother != null) {
      if (_historyContainsImageRequest(history)) {
        return ImageRequestResult(
          detected: true,
          reason: 'explicit_another_photo',
          matchedPhrase: mAnother.group(0) ?? '',
          score: 85,
        );
      }
      return ImageRequestResult(
        detected: false,
        reason: 'another_but_no_prior_image',
        matchedPhrase: mAnother.group(0) ?? '',
        score: 10,
      );
    }

    final mType = _typeRequestRegex.firstMatch(lower);
    if (mType != null) {
      final verbNear = RegExp(
        r"\b(env[ií]a|manda|muestr|ens[eé]ñ|haz|saca|mu[eé]strame|m[áa]ndame|quiero|puedes|podr[ií]as?)\b",
        caseSensitive: false,
      );
      final ctx = 30;
      final idx = (mType.start - ctx).clamp(0, lower.length);
      final window = lower.substring(idx, (mType.end + ctx).clamp(0, lower.length));
      if (verbNear.hasMatch(window)) {
        return ImageRequestResult(
          detected: true,
          reason: 'type_with_verb',
          matchedPhrase: mType.group(0) ?? '',
          score: 80,
        );
      }
    }

    for (final kw in _keywords) {
      if (lower.contains(kw)) {
        if (_isAmbiguousShort(lower, kw)) {
          return ImageRequestResult(detected: false, reason: 'ambiguous_short', matchedPhrase: kw, score: 5);
        }
        final verbNearby = RegExp(
          r"\b(env[ií]a|manda|muestr|ens[eé]ñ|haz|saca|mu[eé]strame|m[áa]ndame|quiero|puedes|podr[ií]as?)\b",
          caseSensitive: false,
        );
        final idx = lower.indexOf(kw);
        final ctxBefore = lower.substring((idx - 20).clamp(0, lower.length), idx);
        final ctxAfter = lower.substring(idx, (idx + kw.length + 20).clamp(0, lower.length));
        if (verbNearby.hasMatch(ctxBefore) || verbNearby.hasMatch(ctxAfter)) {
          return ImageRequestResult(detected: true, reason: 'keyword_with_verb', matchedPhrase: kw, score: 75);
        }
        final imageWords = ['foto', 'selfie', 'imagen', 'retrato', 'cara', 'rostro'];
        final count = imageWords.where((w) => lower.contains(w)).length;
        if (count >= 2) {
          return ImageRequestResult(detected: true, reason: 'multiple_image_words', matchedPhrase: kw, score: 70);
        }
        return ImageRequestResult(detected: false, reason: 'keyword_low_confidence', matchedPhrase: kw, score: 30);
      }
    }

    // Si el usuario envía un ack/polite followup ("vale, cuando puedas") y en el
    // historial hay una promesa explícita del asistente de enviar una foto que
    // aún no se materializó (no hay m.isImage posterior), interpretamos esto
    // como continuación de la petición y la contamos como petición activa.
    if (_isLikelyFollowup(lower, history) && _assistantPromisedImage(history)) {
      final matched = _lastHistoryMatch(history) ?? '';
      return ImageRequestResult(
        detected: true,
        reason: 'ack_followup_to_pending_image',
        matchedPhrase: matched.isNotEmpty ? matched : 'ack_followup',
        score: 80,
      );
    }

    // No forzar petición basada únicamente en historial: comentarios sobre
    // la imagen previa (p. ej. "qué bonita la foto") NO deben considerarse
    // como petición. Las peticiones explícitas como "envíame otra foto" ya
    // quedan cubiertas por `_anotherPhotoRegex` arriba.
    final res = ImageRequestResult(detected: false, reason: 'none', matchedPhrase: '', score: 0);
    Log.d('ImageRequestService.detectImageRequest -> $res', tag: 'IMAGE_REQ');
    return res;
  }

  static bool isImageRequested({required String text, List<Message>? history}) {
    final res = detectImageRequest(text: text, history: history);
    return res.detected;
  }

  static bool _isAmbiguousShort(String lowerText, String kw) {
    final ambiguousShortWords = {'cara', 'rostro', 'retrato', 'imagen', 'foto', 'selfie'};
    if (ambiguousShortWords.contains(kw)) {
      if (lowerText.length <= 12) return true;
      final onlyKeyword = RegExp('^\\s*${RegExp.escape(kw)}\\s*\$');
      if (onlyKeyword.hasMatch(lowerText)) return true;
    }
    return false;
  }

  static bool _historyContainsImageRequest(List<Message>? history) {
    if (history == null || history.isEmpty) return false;
    final recent = history.length <= 5 ? history : history.sublist(history.length - 5);
    for (final m in recent.reversed) {
      // Si el asistente ya envió una imagen, consideramos que hay imagen previa
      if (m.sender == MessageSender.assistant && m.isImage) return true;
      final l = m.text.toLowerCase();
      for (final p in _highConfidenceKeywords) {
        if (l.contains(p)) return true;
      }
      for (final rx in _explicitRegex) {
        if (rx.hasMatch(l)) return true;
      }
    }
    // registrar si hay una frase coincidente en el historial (para diagnóstico)
    final matched = _lastHistoryMatch(history);
    if (matched != null) {
      Log.d('ImageRequestService.history matched phrase: $matched', tag: 'IMAGE_REQ');
    }
    return false;
  }

  static String? _lastHistoryMatch(List<Message>? history) {
    if (history == null || history.isEmpty) return null;
    final recent = history.length <= 10 ? history : history.sublist(history.length - 10);
    for (final m in recent.reversed) {
      if (m.sender == MessageSender.assistant && m.isImage) return m.text.isNotEmpty ? m.text : 'assistant_image';
      final l = m.text.toLowerCase();
      for (final p in _highConfidenceKeywords) {
        if (l.contains(p)) return m.text;
      }
      for (final rx in _explicitRegex) {
        final r = rx.firstMatch(l);
        if (r != null) return m.text;
      }
    }
    return null;
  }

  static bool _assistantPromisedImage(List<Message>? history) {
    if (history == null || history.isEmpty) return false;
    // Buscamos en los últimos 5 mensajes para promesas pendientes.
    final recent = history.length <= 5 ? history : history.sublist(history.length - 5);
    bool foundPromise = false;
    for (final m in recent.reversed) {
      if (m.sender == MessageSender.assistant) {
        final l = m.text.toLowerCase();
        // Si ya envió una imagen tras la promesa, la promesa no está pendiente
        if (m.isImage) return false;
        // Buscar frases que indiquen promesa/confirmación de envío
        for (final p in _highConfidenceKeywords) {
          if (l.contains(p)) {
            foundPromise = true;
            break;
          }
        }
        // también chequear expresiones simples de promesa
        if (!foundPromise &&
            RegExp(
              r"\b(ahora mismo|ahora|enseguida|luego te la mando|te la mando ahora)\b",
              caseSensitive: false,
            ).hasMatch(l)) {
          foundPromise = true;
        }
        if (foundPromise) return true;
      }
      // Si encontramos un mensaje del usuario después de la promesa, no invalida la promesa
      // porque puede ser un followup (ej. "vale, cuando puedas"). Simplemente seguimos.
    }
    return false;
  }

  static bool _isLikelyFollowup(String lowerText, List<Message>? history) {
    // Heurística simple: frases cortas, contenidas en 1-3 palabras, o que sean
    // sólo ack/ok/vale/cuando puedas etc. También aceptamos mensajes que no
    // contengan solicitudes explícitas y que tengan poca puntuación.
    final tokens = lowerText.split(RegExp(r"\s+"));
    if (tokens.length <= 3) return true;
    // Si el texto contiene palabras que normalmente no son solicitudes explícitas
    // y no contiene verbos como 'manda', 'envía', 'quiero', lo es más probable.
    final explicitVerb = RegExp(
      r"\b(env[ií]a|manda|muestr|ens[eé]ñ|haz|saca|mu[eé]strame|m[áa]ndame|quiero|puedes|podr[ií]as?)\b",
      caseSensitive: false,
    );
    if (!explicitVerb.hasMatch(lowerText)) return true;
    return false;
  }
}
