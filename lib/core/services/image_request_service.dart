import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ImageRequestResult {
  final bool detected;
  final String reason;
  final String matchedPhrase;
  final int score; // 0..100

  ImageRequestResult({
    required this.detected,
    this.reason = '',
    this.matchedPhrase = '',
    this.score = 0,
  });

  @override
  String toString() =>
      'ImageRequestResult(detected: $detected, reason: $reason, matched: "$matchedPhrase", score: $score)';
}

class ImageRequestService {
  // Replaced exact phrase list by regex-based detection below.

  // _keywords removed: use _imageWordRegex instead.

  // Regex to detect image-related words (Spanish + common English variants).
  static final RegExp _imageWordRegex = RegExp(
    r'\b(foto|fotos|fotito|fotitos|fotograf[ií]a|fotograf[ií]as|selfie|selfi|imagen|imagenes|imagenito|imagenitos|retrato|retratos|rostro|cara|cuerpo|perfil|picture|picture(s)?|photo|photos|pic|screenshot|captura|headshot|portrait|foto_de_perfil)\b',
    caseSensitive: false,
  );

  // Regex que matchea exactamente una única palabra de imagen (mensaje corto "foto")
  static final RegExp _onlyImageWordRegex = RegExp(
    r'^\s*(?:foto|fotos|fotito|selfie|selfi|imagen|imagenito|retrato|rostro|cara|picture|photo|pic|screenshot)\s*[.!?]?\s*$',
    caseSensitive: false,
  );

  // Regex to detect send/re-send actions (envíame, reenvíame, mándame, manda, etc.).
  // Usamos formas tolerantes para cubrir variantes con/without accents and common suffixes.
  static final RegExp _sendVerbRegex = RegExp(
    // cubrir enviar/envíame/reenvíame, manda/mándame, pásame/pasame, comparte, adjunta
    r'\b(?:re)?env[ií]\w*\b|\bm[áa]nd\w*\b|\bpas[ae]\w*\b|\bcompart\w*\b|\badju?n?ta\w*\b|\bsube\w*\b',
    caseSensitive: false,
  );

  // Se eliminaron las regex explícitas basadas en verbos. La detección usa:
  // - _highConfidenceKeywords (frases exactas)
  // - conteo de palabras de imagen
  // - heurística estructural (posesivos/comparativos)
  // - detección de 'otra foto' y tipos (full body, close-up, ...)

  // Consolidated negative patterns into a single regex for broader coverage.
  static final RegExp _negativePatternsRegex = RegExp(
    r'\b(?:no quiero (?:foto|imagen|fotograf[ií]a)|no me (?:mandes|env[ií]es) (?:foto|imagen)|no necesito (?:foto|imagen)|de ninguna manera|ni loco|nunca|no,? gracias|para nada)\b',
    caseSensitive: false,
  );

  static final RegExp _anotherPhotoRegex = RegExp(
    r'\b(otra foto|otra imagen|otra vez|otra similar|otra por favor|otra, por favor|otra igual|otra distinta|another photo|another picture|otra?)\b',
    caseSensitive: false,
  );
  static final RegExp _typeRequestRegex = RegExp(
    r'\b(cuerpo entero|de cuerpo entero|full body|medio cuerpo|plano medio|primer plano|close[- ]?up|close ?up|primerplano|primer_plano|plano_detalle|headshot|más sexy|más natural|más grande|detalle|closeup|retrato)\b',
    caseSensitive: false,
  );

  // Regex amplio para frases afirmativas cortas.
  static final RegExp _affirmativeRegex = RegExp(
    r'\b(?:si+|sí+|sip+|sii+|claro|obvio|vale|ok(?:ay)?|perfecto|adelante|por supuesto|dale|venga|claro que sí|por supuesto que sí|sí claro|sí,|si claro|yeah|yep|sure|okey)\b',
    caseSensitive: false,
  );

  // Regex amplio para negaciones cortas.
  static final RegExp _negativeRegex = RegExp(
    r'\b(?:no|nop|nope|no gracias|nah|na|nunca|de ninguna manera)\b',
    caseSensitive: false,
  );

  // Nota: antes usábamos una regex explícita para ack/followups; en su lugar
  // usamos una heurística flexible que evalúa si el mensaje del usuario es
  // corto/poco informativo (un followup) y si hay una promesa pendiente del
  // asistente en el historial reciente.

  static ImageRequestResult detectImageRequest({
    required String text,
    List<Message>? history,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return ImageRequestResult(
        detected: false,
        reason: 'empty',
      );
    }
    final lower = trimmed.toLowerCase();

    final negM = _negativePatternsRegex.firstMatch(lower);
    if (negM != null) {
      return ImageRequestResult(
        detected: false,
        reason: 'negative_match',
        matchedPhrase: negM.group(0) ?? '',
      );
    }

    // Alta confianza si el texto contiene una acción de envío y una palabra de imagen.
    if (_sendVerbRegex.hasMatch(lower) && _imageWordRegex.hasMatch(lower)) {
      return ImageRequestResult(
        detected: true,
        reason: 'high_confidence_regex',
        matchedPhrase: lower,
        score: 95,
      );
    }

    // Nueva regla simple y conservadora:
    // Si en el historial reciente hay un mensaje del asistente que mencionó
    // una palabra de imagen (por ejemplo "foto") y el usuario responde con
    // una afirmación corta («si», «claro», «vale», etc.) o con una negación
    // corta («no», «no gracias»), entonces actuamos como petición confirmada
    // o negada respectivamente. Esto evita depender de verbos y es muy
    // directa: palabra de imagen (asistente) + confirmación del usuario.
    final assistantMention = _lastAssistantImageMention(history);
    if (assistantMention != null) {
      if (_containsAffirmation(lower)) {
        return ImageRequestResult(
          detected: true,
          reason: 'followup_affirmative_to_assistant_image_mention',
          matchedPhrase: assistantMention,
          score: 95,
        );
      }
      if (_containsNegation(lower)) {
        return ImageRequestResult(
          detected: false,
          reason: 'followup_negative_to_assistant_image_mention',
          matchedPhrase: assistantMention,
        );
      }
    }

    // Ya no usamos expresiones basadas en verbos; en su lugar, si el texto
    // contiene una frase de alta confianza o la estructura sugiere petición,
    // la marcamos.
    if (_structureSuggestsRequest(lower)) {
      return ImageRequestResult(
        detected: true,
        reason: 'structural_request',
        matchedPhrase: lower,
        score: 85,
      );
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
        r'\b(env[ií]a|manda|muestr|ens[eé]ñ|haz|saca|mu[eé]strame|m[áa]ndame|quiero|queri[í]a|puedes|podr[ií]as?)\b',
        caseSensitive: false,
      );
      final ctx = 30;
      final idx = (mType.start - ctx).clamp(0, lower.length);
      final window = lower.substring(
        idx,
        (mType.end + ctx).clamp(0, lower.length),
      );
      if (verbNear.hasMatch(window)) {
        return ImageRequestResult(
          detected: true,
          reason: 'type_with_verb',
          matchedPhrase: mType.group(0) ?? '',
          score: 80,
        );
      }
    }

    if (_imageWordRegex.hasMatch(lower)) {
      final m = _imageWordRegex.firstMatch(lower);
      final kw = m?.group(0) ?? '';
      if (kw.isNotEmpty && _isAmbiguousShort(lower, kw)) {
        return ImageRequestResult(
          detected: false,
          reason: 'ambiguous_short',
          matchedPhrase: kw,
          score: 5,
        );
      }
      if (_structureSuggestsRequest(lower)) {
        return ImageRequestResult(
          detected: true,
          reason: 'structural_request',
          matchedPhrase: kw.isNotEmpty ? kw : lower,
          score: 80,
        );
      }
      // Conteo de apariciones de palabras de imagen usando regex
      final count = _imageWordRegex.allMatches(lower).length;
      if (count >= 2) {
        return ImageRequestResult(
          detected: true,
          reason: 'multiple_image_words',
          matchedPhrase: kw.isNotEmpty ? kw : lower,
          score: 70,
        );
      }
      return ImageRequestResult(
        detected: false,
        reason: 'keyword_low_confidence',
        matchedPhrase: kw.isNotEmpty ? kw : lower,
        score: 30,
      );
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
    final res = ImageRequestResult(
      detected: false,
      reason: 'none',
    );
    Log.d('ImageRequestService.detectImageRequest -> $res', tag: 'IMAGE_REQ');
    return res;
  }

  static bool _structureSuggestsRequest(String lowerText) {
    // Requiere presencia de palabra de imagen
    if (!_imageWordRegex.hasMatch(lowerText)) return false;

    // Posesivos o pronombres que indican "tu foto", "foto tuya", "te" etc.
    final possessive = RegExp(
      r'\b(?:mi|mio|mía|mia|tu|tuyo|tuya|su|sus|de ti|de usted|de vosotros|de ustedes|para ti|para usted)\b',
      caseSensitive: false,
    );
    if (possessive.hasMatch(lowerText)) return true;

    // Comparativos/descritores que suelen aparecer cuando se pide una foto similar
    final comparative = RegExp(
      r'\b(parecid|parecida|parecido|similar|como|igual|parece|asemeja|tal como)\b',
      caseSensitive: false,
    );
    if (comparative.hasMatch(lowerText)) return true;

    // Frases que suelen indicar petición indirecta: "me la mandas", "puedes mandarme",
    // "podrías enviarme", etc. Detectamos con patrón flexible sin listar cada verbo.
    final requestish = RegExp(
      r'\b(puedes|podr[ií]as|podr[ií]a|me la|mela|mand(a|ame|arme)|env[ií]a(me|la|mela)?|reenv[ií]a(me|la)?)\b',
      caseSensitive: false,
    );
    if (requestish.hasMatch(lowerText)) return true;

    // Detectar formas verbales en condicional/subjuntivo/condicional like -ría/-ría (quisiera, querría)
    final iAverb = RegExp(r'\b\w{3,}[ríí]a\b', caseSensitive: false);
    if (iAverb.hasMatch(lowerText)) return true;

    return false;
  }

  // Devuelve el texto del último mensaje del asistente (reciente) que menciona
  // una palabra relacionada con imagen y que no sea ya un mensaje de imagen.
  static String? _lastAssistantImageMention(List<Message>? history) {
    if (history == null || history.isEmpty) return null;
    final recent = history.length <= 8
        ? history
        : history.sublist(history.length - 8);
    for (final m in recent.reversed) {
      if (m.sender == MessageSender.assistant) {
        if (m.isImage) continue; // ya envió imagen, no contamos
        final l = m.text.toLowerCase();
        // si contiene palabra relacionada con imagen o un verbo de envío
        if (_imageWordRegex.hasMatch(l) || _sendVerbRegex.hasMatch(l)) {
          return m.text;
        }
      }
    }
    return null;
  }

  // Affirmation and negation regexes (replacing word lists)
  // Note: anchored checks and short-message heuristics are applied in helpers.
  static final RegExp _affirmativeRegexWide = _affirmativeRegex;
  static final RegExp _negativeRegexWide = _negativeRegex;

  static bool _containsAffirmation(String lowerText) {
    // Tokeniza y busca palabras de afirmación simples.
    final tokens = lowerText
        .replaceAll(RegExp(r'[^\wáéíóúñü]', caseSensitive: false), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return false;
    // Si el mensaje es muy corto (<=3 tokens) y contiene cualquiera de las
    // afirmativas, lo consideramos confirmación.
    if (tokens.length <= 3 && _affirmativeRegexWide.hasMatch(lowerText)) {
      return true;
    }
    // También aceptar frases que empiezan con una afirmación larga ("sí, envíamela")
    if (RegExp(
      r'^\s*(?:si|sí|claro|vale|ok|perfecto|por supuesto|dale|venga)\b',
      caseSensitive: false,
    ).hasMatch(lowerText)) {
      return true;
    }
    return false;
  }

  static bool _containsNegation(String lowerText) {
    final t = lowerText.trim();
    if (_negativeRegexWide.hasMatch(t)) return true;
    // exact match or start
    if (RegExp(
      r'^\s*(?:no|nop|nope|no gracias|nah)\b',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    return false;
  }

  static bool isImageRequested({required String text, List<Message>? history}) {
    final res = detectImageRequest(text: text, history: history);
    return res.detected;
  }

  static bool _isAmbiguousShort(String lowerText, String kw) {
    // Considerar ambiguo si el mensaje es solamente una palabra de imagen o muy corto
    if (_onlyImageWordRegex.hasMatch(lowerText)) return true;
    if (lowerText.trim().length <= 12 &&
        _imageWordRegex.hasMatch(lowerText) &&
        _imageWordRegex.allMatches(lowerText).length == 1) {
      return true;
    }
    return false;
  }

  static bool _historyContainsImageRequest(List<Message>? history) {
    if (history == null || history.isEmpty) return false;
    final recent = history.length <= 5
        ? history
        : history.sublist(history.length - 5);
    for (final m in recent.reversed) {
      // Si el asistente ya envió una imagen, consideramos que hay imagen previa
      if (m.sender == MessageSender.assistant && m.isImage) return true;
      final l = m.text.toLowerCase();
      // Si en el historial hay un envío explícito (regex) o mención de imagen,
      // lo consideramos como petición previa.
      if ((_sendVerbRegex.hasMatch(l) && _imageWordRegex.hasMatch(l)) ||
          _imageWordRegex.hasMatch(l) ||
          _structureSuggestsRequest(l)) {
        return true;
      }
    }
    // registrar si hay una frase coincidente en el historial (para diagnóstico)
    final matched = _lastHistoryMatch(history);
    if (matched != null) {
      Log.d(
        'ImageRequestService.history matched phrase: $matched',
        tag: 'IMAGE_REQ',
      );
    }
    return false;
  }

  static String? _lastHistoryMatch(List<Message>? history) {
    if (history == null || history.isEmpty) return null;
    final recent = history.length <= 10
        ? history
        : history.sublist(history.length - 10);
    for (final m in recent.reversed) {
      if (m.sender == MessageSender.assistant && m.isImage) {
        return m.text.isNotEmpty ? m.text : 'assistant_image';
      }
      final l = m.text.toLowerCase();
      if ((_sendVerbRegex.hasMatch(l) && _imageWordRegex.hasMatch(l)) ||
          _imageWordRegex.hasMatch(l) ||
          _structureSuggestsRequest(l)) {
        return m.text;
      }
    }
    return null;
  }

  static bool _assistantPromisedImage(List<Message>? history) {
    if (history == null || history.isEmpty) return false;
    // Buscamos en los últimos 5 mensajes para promesas pendientes.
    final recent = history.length <= 5
        ? history
        : history.sublist(history.length - 5);
    bool foundPromise = false;
    for (final m in recent.reversed) {
      if (m.sender == MessageSender.assistant) {
        final l = m.text.toLowerCase();
        // Si ya envió una imagen tras la promesa, la promesa no está pendiente
        if (m.isImage) return false;
        // Buscar frases que indiquen promesa/confirmación de envío
        if (_sendVerbRegex.hasMatch(l) && _imageWordRegex.hasMatch(l)) {
          foundPromise = true;
        }
        // también chequear expresiones simples de promesa
        if (!foundPromise &&
            RegExp(
              r'\b(ahora mismo|ahora|enseguida|luego te la mando|te la mando ahora)\b',
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
    final tokens = lowerText.split(RegExp(r'\s+'));
    if (tokens.length <= 3) return true;
    // Si el texto contiene palabras que normalmente no son solicitudes explícitas
    // y no contiene verbos como 'manda', 'envía', 'quiero', lo es más probable.
    final explicitVerb = RegExp(
      r'\b(env[ií]a|manda|muestr|ens[eé]ñ|haz|saca|mu[eé]strame|m[áa]ndame|quiero|puedes|podr[ií]as?)\b',
      caseSensitive: false,
    );
    if (!explicitVerb.hasMatch(lowerText)) return true;
    return false;
  }
}
