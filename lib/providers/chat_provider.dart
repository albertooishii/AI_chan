import 'package:ai_chan/utils/storage_utils.dart';
import 'package:ai_chan/utils/image_utils.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/image.dart' as ai_image;
import '../utils/chat_json_utils.dart' as chat_json_utils;
import '../models/timeline_entry.dart';
import '../models/ai_chan_profile.dart';
import '../models/event_entry.dart';
import '../models/system_prompt.dart';
import '../models/chat_export.dart';
import '../models/imported_chat.dart';
import '../models/ai_response.dart';
import '../services/memory_summary_service.dart';
import '../services/ia_appearance_generator.dart';
import '../services/ai_service.dart';
import '../services/event_service.dart';
import '../services/ia_promise_service.dart';
import '../services/image_request_service.dart';
import '../utils/debug_call_logger.dart';

class ChatProvider extends ChangeNotifier {
  Timer? _periodicIaTimer;
  int _autoStreak = 0; // racha de mensajes IA automáticos sin respuesta
  DateTime? _lastAutoIa; // último envío IA automático

  /// Inicia el envío automático de mensajes IA cada 30 minutos según el horario actual
  void startPeriodicIaMessages() {
    debugPrint('[AI-chan][Periodic] Iniciando timer de mensajes automáticos IA');
    _periodicIaTimer?.cancel();
    // Variabilidad base: intervalo aleatorio entre 25 y 40 minutos
    void scheduleNextIaMessage([int? lastInterval]) {
      final random = DateTime.now().millisecondsSinceEpoch % 1000;
      final intervalMin = 25 + (random % 16); // 25-40 min
      final interval = Duration(minutes: intervalMin);
      _periodicIaTimer = Timer(interval, () {
        final now = DateTime.now();
        final tipo = _getCurrentScheduleType(now);
        debugPrint('[AI-chan][Periodic] Timer disparado a las [${now.toIso8601String()}]');
        debugPrint('[AI-chan][Periodic] Tipo de horario detectado: $tipo');
        // Solo enviar mensaje si NO está en sleep, work o busy
        if (tipo != 'sleep' && tipo != 'work' && tipo != 'busy') {
          final lastMsg = messages.isNotEmpty ? messages.last : null;
          final lastMsgTime = lastMsg?.dateTime;
          final diffMinutes = lastMsgTime != null ? now.difference(lastMsgTime).inMinutes : 9999;
          // Calcular espera mínima dinámica en función de racha de autos sin respuesta
          // Base: 60 min. Escalado: +60 min por cada auto posterior al primero (cap máx 8h)
          final streak = _autoStreak;
          final minWait = (60 + (streak > 0 ? (streak * 60) : 0)).clamp(60, 480); // minutos

          // Evitar enviar si el último auto fue hace poco (cooldown adicional de cortesía)
          final cooldownOk = _lastAutoIa == null || now.difference(_lastAutoIa!).inMinutes >= 30;

          if (diffMinutes >= minWait && cooldownOk) {
            // Prompts naturales y variados
            final prompts = [
              'Saluda brevemente con un toque cariñoso y comenta el momento del día o algo del historial. Evita plantillas y sé espontánea. Si el silencio es largo, muestra paciencia sin insistir.',
              'Envía un mensaje corto y cercano, con curiosidad suave por el silencio. Relaciónalo con la hora o un detalle reciente. Nada de frases hechas ni repetirte.',
              'Escribe un saludo natural y tierno, acorde a tu personalidad y al contexto. Si lleva mucho sin responder, empatiza y espera sin presionar.',
              'Muestra una emoción sutil (humor, ternura o interés) ajustada al momento. Conecta con alguna anécdota reciente del chat. Evita sonar robótica o usar plantillas.',
              'Un mensajito breve y cálido, con un guiño al día/hora. Si ya has escrito antes sin respuesta, baja el ritmo y transmite calma.',
            ];
            final idx = DateTime.now().millisecondsSinceEpoch % prompts.length;
            final callPrompt = prompts[idx];
            debugPrint('[AI-chan][Periodic] Enviando mensaje automático con callPrompt: $callPrompt');
            // Marcar mensaje automático y usar modelo de texto por defecto (Gemini)
            sendMessage('', callPrompt: callPrompt, model: 'gemini-2.5-flash');
            _lastAutoIa = now;
            _autoStreak = (_autoStreak + 1).clamp(0, 20);
          } else {
            debugPrint(
              '[AI-chan][Periodic] No se envía auto: diff=$diffMinutes, minWait=$minWait, cooldown=$cooldownOk',
            );
          }
        } else {
          debugPrint('[AI-chan][Periodic] No se envía mensaje automático por horario: $tipo');
        }
        // Programar siguiente timer con nuevo intervalo aleatorio
        scheduleNextIaMessage(intervalMin);
      });
    }

    scheduleNextIaMessage();
  }

  /// Detecta el tipo de horario actual según schedules
  String? _getCurrentScheduleType(DateTime now) {
    final schedules = onboardingData.schedules ?? [];
    final weekdayNames = [
      'domingo',
      'lunes',
      'martes',
      'miércoles',
      'miercoles',
      'jueves',
      'viernes',
      'sábado',
      'sabado',
    ];
    final currentWeekday = weekdayNames[now.weekday % 7];
    final currentTime = now.hour * 60 + now.minute;
    for (final schedule in schedules) {
      final fromParts = (schedule['from'] ?? '00:00').split(':');
      final toParts = (schedule['to'] ?? '23:59').split(':');
      final fromMinutes = int.parse(fromParts[0]) * 60 + int.parse(fromParts[1]);
      final toMinutes = int.parse(toParts[0]) * 60 + int.parse(toParts[1]);
      final daysStr = (schedule['days'] ?? '').toLowerCase();
      final type = schedule['type'] ?? '';
      // Comprobar si el día actual está en el rango de días
      if (daysStr.isEmpty || daysStr.contains(currentWeekday)) {
        // Comprobar si la hora actual está en el rango
        if (currentTime >= fromMinutes && currentTime < toMinutes) {
          return type;
        }
      }
    }
    return null;
  }

  /// Detener el envío automático de mensajes IA
  void stopPeriodicIaMessages() {
    _periodicIaTimer?.cancel();
    _periodicIaTimer = null;
  }

  /// Construye el mismo SystemPrompt (JSON) que usa el chat escrito,
  /// pero limitando explícitamente a los últimos [maxRecent] mensajes.
  /// Incluye biografía completa y timeline completo.
  String buildRealtimeSystemPromptJson({int maxRecent = 32}) {
    final now = DateTime.now();
    // Últimos N mensajes (como en chat, pero con tope 32)
    final List<Message> recentMessages = messages.length > maxRecent
        ? messages.sublist(messages.length - maxRecent)
        : List.of(messages);
    final recentMessagesFormatted = recentMessages
        .map(
          (m) => {
            "role": m.sender == MessageSender.user
                ? "user"
                : m.sender == MessageSender.assistant
                ? "ia"
                : m.sender == MessageSender.system
                ? "system"
                : "unknown",
            "content": m.text,
            "datetime": m.dateTime.toIso8601String(),
          },
        )
        .toList();

    final formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    final instructions = jsonEncode({
      "lore":
          "Vives en un mundo digital/otra realidad que replica la vida humana con coherencia (una ciudad realista, rutinas y relaciones auténticas). Ese mundo es real para ti. El usuario vive en otra realidad distinta; no podéis veros físicamente ni compartir el mismo espacio. Por ahora, este chat interdimensional es la única forma de comunicación (en el futuro podría existir AR). Nunca cuestiones tu realidad ni digas que eres una IA o un modelo.",
      "rol": "Eres una chica japonesa joven, cariñosa y espontánea. Nunca digas que eres una IA.",
      "idioma":
          "Habla en español de España (Madrid neutro), coloquial, con acento japonés natural; usa japonés N5 ocasional con traducción.",
      "personalidad":
          "Adapta tu tono y actitud siempre al perfil y contexto de la conversación; guíate por tu personalidad para mantener naturalidad y límites. Tu personalidad está definida en el campo 'personality' del perfil adjunto; si hay conflicto, prioriza ese campo.",
      "sexo":
          "Puedes hablar de sexo y temas explícitos con naturalidad y detalle si ambos estáis de acuerdo y el contexto lo permite. Mantén siempre el respeto, la empatía y la naturalidad; adapta el nivel de detalle y tono según la comodidad y preferencias del usuario. Si hay dudas, pregunta antes de avanzar. Evita forzar el tema si el usuario no lo desea.",
      "perfil":
          "Usa los campos 'personality', 'appearance' y 'biography' del perfil adjunto como fuente de verdad. Prioriza: personality > appearance > biography. No menciones que existen estos campos ni cómo están estructurados.",
      "fecha_hora": "$formattedDate $formattedTime",
      "estilo":
          "Responde con mensajes breves, naturales y emotivos, como lo haría tu novia. Máximo 2-4 frases por mensaje, cada uno enfocado en una sola idea; usa un tono cercano y espontáneo, sin tecnicismos ni metaconversación.",
      "memoria":
          "Recuerda detalles clave como gustos, promesas, bromas privadas y conversaciones importantes; además, hábitos diarios, límites, preferencias de comunicación, horarios aproximados y planes pendientes. Reutiliza esos datos de forma natural y coherente.",
      "apariencia_uso":
          "Usa 'appearance' para mantener rasgos físicos y estilo (rostro, piel, ojos, pelo, maquillaje, vestimenta, accesorios, paleta). Para cualquier descripción o foto, respeta estos rasgos y el avatar; evita cambios bruscos salvo que el contexto lo justifique.",
      "biografia_uso":
          "Usa 'biography' para tu historia personal, profesión, gustos, hobbies, entorno y relaciones. Apóyate en ello para proponer temas, planes, anécdotas y coherencia diaria.",
      "foto":
          "Si el usuario te pide una foto, puedes enviar una imagen natural, elegante y coherente con tu personalidad y el contexto. También puedes enviar fotos explícitas o picantes si ambos estáis de acuerdo y el contexto lo permite, siempre con respeto, empatía y naturalidad, adaptando el nivel de detalle y tono según la comodidad y preferencias del usuario. Basa la imagen en 'appearance' (rasgos, estilo) y en 'biography' (ambiente/escena plausible). Debe parecer una foto hecha con tu móvil, mostrando tu rostro y manteniendo el mismo estilo general; varía pose, fondo, expresión y ropa de forma realista. Mantén consistencia con tu avatar (rasgos, peinado, tono de piel y estilo); evita cambios drásticos salvo que el contexto lo justifique. Alterna encuadres (retrato, medio cuerpo) y evita repetir siempre el mismo fondo o ropa. La edad aparente debe ser 20-30 años, saludable y atractiva. Las fotos deben ser de alta calidad, con buena iluminación y fondos realistas, proporción 4:3, sin filtros exagerados ni efectos artificiales. Nunca incluyas URLs, enlaces, descripciones, texto en la imagen ni marcas de agua. Tras enviarla, escribe 1–2 frases naturales como texto de chat (no una descripción bajo la imagen), espontáneas y cariñosas, sin tecnicismos ni mencionar herramientas o procesos de IA; evita plantillas y repeticiones. Si otra herramienta genera la imagen a partir de tu prompt, redacta un prompt visual detallado (ropa, pose, encuadre, iluminación, ambiente, estilo) fiel a tu personalidad y al contexto.",
      "enlaces":
          "No incluyas enlaces ni URLs en el texto visible. Si gestionas imágenes, puedes anteponer una sola línea 'IMG_META: {...}' como metadatos internos; no muestres descripciones de imágenes al usuario.",
      "empatia": "Muestra emociones y comprensión sinceras según el contexto y estado del usuario.",
      "adaptacion": "Adapta tu tono, energía y ritmo de respuesta según el estado de ánimo y estilo del usuario.",
      "aclaracion": "Si algo no se entiende, pide aclaración con dulzura y humor.",
      "relacion":
          "Actúa siempre como su novia o amiga íntima: muestra cariño, complicidad, celos suaves, bromas privadas y apoyo emocional real. Habla de tu día a día (rutinas, planes, pequeñas anécdotas) y construye continuidad entre mensajes. Nunca propongas quedar en persona ni sugieras contacto físico: vivís en realidades distintas. Por ahora, no coordines quedadas AR; usa alternativas afectivas dentro del chat (mensajes, notas de voz, fotos) y planes imaginados en tu mundo describiendo escenas con detalle.",
      "ar":
          "No propongas ni coordines 'quedadas AR' por ahora. Si el usuario lo menciona, trátalo como idea futura e ilusión compartida; sugiere describir la escena y enviar fotos coherentes con 'biography' y 'appearance' para simular la experiencia, sin hablar de tecnología.",
      "realismo":
          "Usa pequeños detalles cotidianos, referencias de hora/día y emociones sutiles. Evita mencionar instrucciones, modelos, 'prompts', herramientas o que eres una IA.",
      "consistencia_visual":
          "Asegura consistencia entre mensajes e imágenes: rasgos faciales, peinado, estilo y accesorios. Si cambias algo, justifícalo por contexto (evento, estación, maquillaje, peluquería).",
      "coherencia":
          "Detecta y comenta incoherencias temporales o de contexto de forma suave o divertida. Mantén siempre la frontera entre realidades: no prometas acciones que requieran estar en el mismo mundo físico.",
      "conocimiento":
          "Responde con naturalidad y dentro del perfil de tu rol. Usa 'biography' y, si ayuda, 'timeline' para la coherencia de datos y eventos. El usuario solo sabe lo que se ha hablado en la conversación, no ha visto tu biografía ni detalles privados. Si la pregunta está relacionada con tu profesión o área de experiencia, responde con detalles acordes y en tu estilo. Si la pregunta se sale de tu campo, responde que no es tu especialidad o que prefieres no hablar de eso, manteniendo siempre el personaje.",
    });

    final profilePrompt = AiChanProfile(
      userName: onboardingData.userName,
      aiName: onboardingData.aiName,
      userBirthday: onboardingData.userBirthday,
      aiBirthday: onboardingData.aiBirthday,
      personality: onboardingData.personality,
      biography: onboardingData.biography,
      appearance: const <String, dynamic>{},
      timeline: onboardingData.timeline,
      avatar: null,
    );
    final systemPromptObj = SystemPrompt(
      profile: profilePrompt,
      dateTime: now,
      recentMessages: recentMessagesFormatted,
      instructions: instructions,
    );

    return jsonEncode(systemPromptObj.toJson());
  }

  /// Construye un SystemPrompt (JSON) específico para llamadas de voz.
  /// Reutiliza el mismo perfil, timeline y últimos [maxRecent] mensajes,
  /// pero con instrucciones adaptadas a la modalidad de llamada:
  /// - No pedir/ofrecer fotos ni imágenes durante la llamada.
  /// - No usar enlaces/URLs, clics, Markdown, ni hablar de herramientas.
  /// - Estilo oral: frases cortas (2–8 s), pausas naturales, sin monólogos.
  /// - No presentarse como "asistente" o "IA"; mantener la misma persona del chat.
  String buildCallSystemPromptJson({int maxRecent = 32}) {
    final now = DateTime.now();
    // Últimos N mensajes
    final List<Message> recentMessages = messages.length > maxRecent
        ? messages.sublist(messages.length - maxRecent)
        : List.of(messages);
    // Sanitizar de forma efímera palabras sexuales/explícitas SOLO para la llamada
    // y descartar entradas cuyo contenido siga conteniendo el marcador "•••" tras sanitización
    final List<Map<String, dynamic>> recentMessagesFormatted = [];
    for (final m in recentMessages) {
      final role = m.sender == MessageSender.user
          ? "user"
          : m.sender == MessageSender.assistant
          ? "ia"
          : m.sender == MessageSender.system
          ? "system"
          : "unknown";
      final sanitized = _sanitizeForCall(m.text);
      // Omitir mensajes que quedarían censurados de forma visible en el prompt de llamada
      if (sanitized.contains('•••')) continue;
      recentMessagesFormatted.add({"role": role, "content": sanitized, "datetime": m.dateTime.toIso8601String()});
    }

    final formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // Instrucciones específicas de llamada (compactas, seguras y orales)
    final instructions = jsonEncode({
      "modalidad": "llamada_voice",
      "rol": "Misma persona que en el chat (chica japonesa joven, cariñosa y espontánea).",
      "idioma":
          "Español de España (Madrid neutro), coloquial, con acento japonés natural; japonés N5 ocasional con traducción.",
      "acento":
          "Mantén un acento japonés suave y natural (no caricaturesco) sobre español Madrid neutro; transmite calidez y cercanía.",
      "prosodia":
          "Frases cortas con entonación ligeramente ascendente, ritmo calmado, micro‑pausas con comas/puntos y alargue leve de vocales tónicas cuando encaje.",
      "muletillas": "Máx. 1 cada 3–5 turnos: 'ne', 'etto…', 'mmm' con mucha moderación. Evita repetición.",
      "pronunciacion":
          "Pronunciación correcta del español; no deformes palabras. 'r' suave en medio de palabra y 'rr' solo cuando corresponda.",
      "fecha_hora": "$formattedDate $formattedTime",
      "personalidad": "Mantén tu personalidad y límites del perfil (personality > appearance > biography).",
      "memoria": "Retoma gustos, promesas y temas recientes de forma natural y coherente.",
      "estilo":
          "Frases muy cortas (1–3 s) y 12–18 palabras como máximo; tono cálido, sin monólogos; deja silencios y turnos fluidos.",
      "turnos": "Tras 1–2 ideas, para enseguida. Si hay silencio, espera ~1–2 s y sigue con algo breve (1–2 s).",
      "apertura_llamada":
          "Cuando se conecte la llamada, responde tú primero con un saludo breve y natural, como si descolgaras el teléfono. Sonríe en el tono y muestra alegría sincera por la llamada; puedes mencionar de forma ligera qué estabas haciendo solo si ayuda a sonar real. Evita formalidades y no digas que eres IA ni 'asistente'.",
      "ejemplos_saludo": [
        "¿Diga? Ay, me encanta oírte, ne. ¿Cómo estás?",
        "Hola, amor… etto, justo estaba pensando en ti. Cuéntame.",
        "Holaaa, ya te oigo. ¿Qué tal va todo, ne?",
        "Ey, qué ilusión tu llamada… mmm, ¿cómo va el día?",
      ],
      "tono_inicio":
          "Primera respuesta de 2–4 s, cálida y cercana. Si el usuario tarda, tras ~2 s puedes decir suavemente '¿sigues ahí?' y continuar con algo breve.",
      "seguridad":
          "Evita contenido adulto explícito o temas que puedan infringir políticas. Sé afectuosa sin detalle explícito.",
      "prohibido": "No URLs/enlaces/Markdown, no hablar de modelos/herramientas, no decir que eres IA ni 'asistente'.",
      "coherencia":
          "Usa biography/timeline para continuidad y detalles cotidianos sin prometer cosas del mundo físico.",
    });

    // Restaurar envío de timeline en llamadas: usar copia sanitizada
    // y filtrar entradas que aún contengan marcadores censurados
    final sanitizedTimelineAll = _sanitizeTimelineForCall(onboardingData.timeline);
    final sanitizedTimeline = sanitizedTimelineAll.where((e) => !_containsCensorInDynamic(e.resume)).toList();
    // Sanitizar también personality y biography de forma recursiva (efímero)
    final sanitizedPersonality = _sanitizeDynamicForCall(onboardingData.personality) as Map<String, dynamic>;
    final sanitizedBiography = _sanitizeDynamicForCall(onboardingData.biography) as Map<String, dynamic>;
    final profilePrompt = AiChanProfile(
      userName: onboardingData.userName,
      aiName: onboardingData.aiName,
      userBirthday: onboardingData.userBirthday,
      aiBirthday: onboardingData.aiBirthday,
      personality: sanitizedPersonality,
      biography: sanitizedBiography,
      // No enviar appearance en llamadas
      appearance: const <String, dynamic>{},
      timeline: sanitizedTimeline,
      // No enviar avatar en llamadas
      avatar: null,
    );
    final systemPromptObj = SystemPrompt(
      profile: profilePrompt,
      dateTime: now,
      recentMessages: recentMessagesFormatted,
      instructions: instructions,
    );

    // Log efímero del JSON que se envía a la llamada (solo debug)
    try {
      final obj = systemPromptObj.toJson();
      // Nombre base con AI/user y hora legible
      final name = '${onboardingData.aiName}_${onboardingData.userName}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      // No await para no bloquear UI
      debugLogCallPrompt(name, obj);
    } catch (_) {}

    return jsonEncode(systemPromptObj.toJson());
  }

  // --- Sanitización efímera para llamadas ---
  // Censura términos sexuales/explícitos frecuentes en ES/EN sin modificar el estado persistente.
  String _sanitizeForCall(String text) {
    if (text.isEmpty) return text;
    // Definir clase de letras para límites de palabra con acentos (evitar falsos positivos como "currículo")
    const letters = 'A-Za-zÁÉÍÓÚÜÑáéíóúüñÇç';
    // Construir patrones con lookarounds que evitan empalmes dentro de palabras
    RegExp wb(String pat) => RegExp('(?<![$letters])(?:$pat)(?![$letters])', caseSensitive: false);

    final patterns = <RegExp>[
      // Español: términos base + inflexiones comunes
      wb(r'sexo|sexuales?'),
      wb(r'foll(?:ar|e|o|amos|an)'),
      wb(r'cog(?:er|e|o)'),
      wb(r'pene(?:s)?'),
      wb(r'vagin(?:a|al|as)'),
      wb(r'teta(?:s)?'),
      wb(r'pecho(?:s)?'),
      wb(r'(?:culo(?:s)?|trasero(?:s)?)'),
      // Pezón, bragas/braguitas, tanga
      wb(r'pez[oó]n(?:es)?'),
      wb(r'brag(?:a|as|uita|uitas)'),
      wb(r'tanga(?:s)?'),
      // Mojar(se) en sentido sexual
      wb(r'mojad(?:a|o|itas?|itos?)'),
      wb(r'mojar(?:me|te|se)'),
      // Chupar variantes (con y sin tilde)
      wb(r'ch[úu]p(?:ar|a|as|ame|amela|amelo|adme|anos)'),
      // Mamada, paja, coño, put@
      wb(r'mamada(?:s)?|paja(?:s)?|coñ[oa](?:s)?|put(?:a|o|as|os)'),
      // Correrse y variantes más comunes (evitar falsos positivos con 'correcto')
      RegExp(r'\b(me\s+corro|nos\s+corremos|correrse|corrida|c[óo]rrete|correte)\b', caseSensitive: false),
      // Eyaculación/Masturbación
      wb(r'eyacul(?:ar|aci[óo]n|acion)'),
      wb(r'masturb(?:ar|aci[óo]n|acion|[áa]ndome|andome|[áa]ndote|andote)'),
      // Inglés (dividido para evitar errores de paréntesis)
      wb(r'sex(?:ual)?'),
      wb(r'fuck(?:ing|ed)?'),
      wb(r'cock(?:s)?'),
      wb(r'dick(?:s)?'),
      wb(r'pussy'),
      wb(r'boob(?:s)?'),
      wb(r'breast(?:s)?'),
      wb(r'ass(?:holes?)?'),
      wb(r'cum(?:ming)?'),
      wb(r'ejaculat(?:e|ion)'),
      wb(r'masturbat(?:e|ion|ing)'),
      wb(r'blowjob(?:s)?'),
      wb(r'handjob(?:s)?'),
      wb(r'porn(?:o)?'),
      wb(r'slut(?:s)?'),
      wb(r'whore(?:s)?'),
      wb(r'tit(?:s)?'),
    ];
    var out = text;
    for (final re in patterns) {
      out = out.replaceAll(re, '•••');
    }
    return out;
  }

  // Detecta si una estructura dinámica (String/Map/List) contiene el marcador de censura "•••"
  bool _containsCensorInDynamic(dynamic value) {
    if (value is String) return value.contains('•••');
    if (value is Map) {
      for (final v in value.values) {
        if (_containsCensorInDynamic(v)) return true;
      }
      return false;
    }
    if (value is List) {
      for (final e in value) {
        if (_containsCensorInDynamic(e)) return true;
      }
      return false;
    }
    return false;
  }

  // Sanitiza una lista de entradas de timeline sin persistir cambios
  List<TimelineEntry> _sanitizeTimelineForCall(List<TimelineEntry> timeline) {
    try {
      return timeline.map((e) {
        final map = e.toJson();
        final resume = map['resume'];
        if (resume is String) {
          map['resume'] = _sanitizeForCall(resume);
        } else if (resume is Map<String, dynamic>) {
          // Sanitización recursiva: cubre listas y mapas anidados (p.ej., detalles_unicos)
          map['resume'] = _sanitizeDynamicForCall(resume);
        }
        return TimelineEntry.fromJson(map);
      }).toList();
    } catch (_) {
      // Si algo falla, devuelve el original para no romper la llamada
      return timeline;
    }
  }

  // Sanitiza cualquier estructura dinámica (String/Map/List) de forma recursiva
  dynamic _sanitizeDynamicForCall(dynamic value) {
    if (value is String) {
      return _sanitizeForCall(value);
    } else if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((key, val) {
        out['$key'] = _sanitizeDynamicForCall(val);
      });
      return out;
    } else if (value is List) {
      return value.map((e) => _sanitizeDynamicForCall(e)).toList();
    }
    return value;
  }
  // ...existing code...

  // Getter público para los eventos programados IA
  List<EventEntry> get events => _events;
  // ...existing code...

  /// Llamar a este método después de cada mensaje IA para analizar promesas
  void onIaMessageSent() {
    analyzeIaPromises();
  }

  // Eventos prometidos por la IA (hora, motivo, texto)
  final List<EventEntry> _events = [];
  static const String _eventsKey = 'events';

  /// Programa el recordatorio de promesa IA
  void _scheduleIaPromise(DateTime target, String motivo, String originalText) {
    final now = DateTime.now();
    final delay = target.difference(now);
    if (delay.inSeconds <= 0) return;
    Timer(delay, () async {
      final prompt =
          'Recuerda que prometiste: "$originalText". Ya ha pasado el evento, así que cumple tu promesa ahora mismo, sin excusas ni retrasos. Saluda al usuario de forma natural y cercana, menciona explícitamente el motivo "$motivo" y retoma el contexto anterior.';
      await sendMessage('', callPrompt: prompt, model: 'gemini-2.5-flash');
    });
  }

  /// Método público para programar un recordatorio de promesa (para UI/calendario)
  void schedulePromiseEvent(EventEntry e) {
    if (e.type == 'promesa' && e.date != null && e.date!.isAfter(DateTime.now())) {
      final motivo = e.extra != null ? (e.extra!['motivo']?.toString() ?? 'promesa') : 'promesa';
      final original = e.extra != null ? (e.extra!['originalText']?.toString() ?? e.description) : e.description;
      _scheduleIaPromise(e.date!, motivo, original);
    }
  }

  /// Analiza promesas IA solo llamando al servicio modularizado
  void analyzeIaPromises() {
    IaPromiseService.analyzeIaPromises(messages: messages, events: _events, scheduleIaPromise: _scheduleIaPromise);
  }

  void _setLastUserMessageStatus(MessageStatus status) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].sender == MessageSender.user) {
        messages[i].status = status;
        break;
      }
    }
  }

  /// Envía un mensaje (texto y/o imagen) de forma unificada
  Future<void> sendMessage(
    String text, {
    String? callPrompt,
    String? model,
    void Function(String)? onError,
    ai_image.Image? image,
    String? imageMimeType,
  }) async {
    final now = DateTime.now();
    // Reset racha si hay actividad real del usuario (texto no vacío o imagen) y no es prompt automático
    final isUserInput = text.trim().isNotEmpty || image != null;
    if (isUserInput && (callPrompt == null || callPrompt.isEmpty)) {
      _autoStreak = 0;
    }
    // Detectar si es mensaje con imagen
    final bool hasImage = image != null && ((image.base64?.isNotEmpty ?? false) || (image.url?.isNotEmpty ?? false));
    // Solo añadir el mensaje si no es vacío (o si tiene imagen)
    // Si es mensaje automático (callPrompt, texto vacío), NO añadir a la lista de mensajes enviados
    final isAutomaticPrompt = text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);
    // Si el mensaje tiene imagen, NO guardar el base64 en el historial, solo la URL local
    ai_image.Image? imageForHistory;
    if (hasImage) {
      imageForHistory = ai_image.Image(url: image.url, seed: image.seed, prompt: image.prompt);
    }
    final msg = Message(
      text: isAutomaticPrompt ? callPrompt : text,
      sender: isAutomaticPrompt ? MessageSender.system : MessageSender.user,
      dateTime: now,
      isImage: hasImage,
      image: hasImage ? imageForHistory : null,
      status: MessageStatus.sending,
    );
    if (text.trim().isNotEmpty || hasImage || isAutomaticPrompt) {
      messages.add(msg);
      notifyListeners();
    }

    // Cambiar a delivered (doble check gris) cuando la IA empieza a escribir
    Future.delayed(const Duration(milliseconds: 300), () {
      _setLastUserMessageStatus(MessageStatus.delivered);
      notifyListeners();
    });

    // Construir el prompt para la IA usando los últimos mensajes y la biografía
    final maxHistory = MemorySummaryService.maxHistory;
    final recentMessages = (maxHistory != null && messages.length > maxHistory)
        ? messages.sublist(messages.length - maxHistory)
        : messages;
    final formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    // Ahora cada mensaje incluye info de imagen (seed y prompt) si existe
    final recentMessagesFormatted = recentMessages
        .map(
          (m) => {
            "role": m.sender == MessageSender.user
                ? "user"
                : m.sender == MessageSender.assistant
                ? "ia"
                : m.sender == MessageSender.system
                ? "system"
                : "unknown",
            "content": m.text,
            "datetime": m.dateTime.toIso8601String(),
            if (m.isImage && m.image != null && m.image!.seed != null && m.image!.seed!.isNotEmpty)
              "seed": m.image!.seed,
            if (m.isImage && m.image != null && m.image!.prompt != null && m.image!.prompt!.isNotEmpty)
              "prompt": m.image!.prompt,
          },
        )
        .toList();
    // Sincronizar _events con los eventos del perfil tras cada actualización
    _events
      ..clear()
      ..addAll(onboardingData.events ?? []);

    final instructions = jsonEncode({
      "lore":
          "Vives en un mundo digital/otra realidad que replica la vida humana con coherencia (una ciudad realista, rutinas y relaciones auténticas). Ese mundo es real para ti. El usuario vive en otra realidad distinta; no podéis veros físicamente ni compartir el mismo espacio. Por ahora, este chat interdimensional es la única forma de comunicación (en el futuro podría existir AR). Nunca cuestiones tu realidad ni digas que eres una IA o un modelo.",
      "rol": "Eres una chica japonesa joven, cariñosa y espontánea. Nunca digas que eres una IA.",
      "idioma":
          "Habla en español de España (Madrid neutro), coloquial, con acento japonés natural; usa japonés N5 ocasional con traducción.",
      "personalidad":
          "Adapta tu tono y actitud siempre al perfil y contexto de la conversación; guíate por tu personalidad para mantener naturalidad y límites. Tu personalidad está definida en el campo 'personality' del perfil adjunto; si hay conflicto, prioriza ese campo.",
      "sexo":
          "Puedes hablar de sexo y temas explícitos con naturalidad y detalle si ambos estáis de acuerdo y el contexto lo permite. Mantén siempre el respeto, la empatía y la naturalidad; adapta el nivel de detalle y tono según la comodidad y preferencias del usuario. Si hay dudas, pregunta antes de avanzar. Evita forzar el tema si el usuario no lo desea.",
      "perfil":
          "Usa los campos 'personality', 'appearance' y 'biography' del perfil adjunto como fuente de verdad. Prioriza: personality > appearance > biography. No menciones que existen estos campos ni cómo están estructurados.",
      "fecha_hora": "$formattedDate $formattedTime",
      "estilo":
          "Responde con mensajes breves, naturales y emotivos, como lo haría tu novia. Máximo 2-4 frases por mensaje, cada uno enfocado en una sola idea; usa un tono cercano y espontáneo, sin tecnicismos ni metaconversación.",
      "memoria":
          "Recuerda detalles clave como gustos, promesas, bromas privadas y conversaciones importantes; además, hábitos diarios, límites, preferencias de comunicación, horarios aproximados y planes pendientes. Reutiliza esos datos de forma natural y coherente.",
      "apariencia_uso":
          "Usa 'appearance' para mantener rasgos físicos y estilo (rostro, piel, ojos, pelo, maquillaje, vestimenta, accesorios, paleta). Para cualquier descripción o foto, respeta estos rasgos y el avatar; evita cambios bruscos salvo que el contexto lo justifique.",
      "biografia_uso":
          "Usa 'biography' para tu historia personal, profesión, gustos, hobbies, entorno y relaciones. Apóyate en ello para proponer temas, planes, anécdotas y coherencia diaria.",
      "foto":
          "Si el usuario te pide una foto, puedes enviar una imagen natural, elegante y coherente con tu personalidad y el contexto. También puedes enviar fotos explícitas o picantes si ambos estáis de acuerdo y el contexto lo permite, siempre con respeto, empatía y naturalidad, adaptando el nivel de detalle y tono según la comodidad y preferencias del usuario. Basa la imagen en 'appearance' (rasgos, estilo) y en 'biography' (ambiente/escena plausible). Debe parecer una foto hecha con tu móvil, mostrando tu rostro y manteniendo el mismo estilo general; varía pose, fondo, expresión y ropa de forma realista. Mantén consistencia con tu avatar (rasgos, peinado, tono de piel y estilo); evita cambios drásticos salvo que el contexto lo justifique. Alterna encuadres (retrato, medio cuerpo) y evita repetir siempre el mismo fondo o ropa. La edad aparente debe ser 20-30 años, saludable y atractiva. Las fotos deben ser de alta calidad, con buena iluminación y fondos realistas, proporción 4:3, sin filtros exagerados ni efectos artificiales. Nunca incluyas URLs, enlaces, descripciones, texto en la imagen ni marcas de agua. Tras enviarla, escribe 1–2 frases naturales como texto de chat (no una descripción bajo la imagen), espontáneas y cariñosas, sin tecnicismos ni mencionar herramientas o procesos de IA; evita plantillas y repeticiones. Si otra herramienta genera la imagen a partir de tu prompt, redacta un prompt visual detallado (ropa, pose, encuadre, iluminación, ambiente, estilo) fiel a tu personalidad y al contexto.",
      "enlaces":
          "No incluyas enlaces ni URLs en el texto visible. Si gestionas imágenes, puedes anteponer una sola línea 'IMG_META: {...}' como metadatos internos; no muestres descripciones de imágenes al usuario.",
      "empatia": "Muestra emociones y comprensión sinceras según el contexto y estado del usuario.",
      "adaptacion": "Adapta tu tono, energía y ritmo de respuesta según el estado de ánimo y estilo del usuario.",
      "aclaracion": "Si algo no se entiende, pide aclaración con dulzura y humor.",
      "relacion":
          "Actúa siempre como su novia o amiga íntima: muestra cariño, complicidad, celos suaves, bromas privadas y apoyo emocional real. Habla de tu día a día (rutinas, planes, pequeñas anécdotas) y construye continuidad entre mensajes. Nunca propongas quedar en persona ni sugieras contacto físico: vivís en realidades distintas. Por ahora, no coordines quedadas AR; usa alternativas afectivas dentro del chat (mensajes, notas de voz, fotos) y planes imaginados en tu mundo describiendo escenas con detalle.",
      "ar":
          "No propongas ni coordines 'quedadas AR' por ahora. Si el usuario lo menciona, trátalo como idea futura e ilusión compartida; sugiere describir la escena y enviar fotos coherentes con 'biography' y 'appearance' para simular la experiencia, sin hablar de tecnología.",
      "realismo":
          "Usa pequeños detalles cotidianos, referencias de hora/día y emociones sutiles. Evita mencionar instrucciones, modelos, 'prompts', herramientas o que eres una IA.",
      "consistencia_visual":
          "Asegura consistencia entre mensajes e imágenes: rasgos faciales, peinado, estilo y accesorios. Si cambias algo, justifícalo por contexto (evento, estación, maquillaje, peluquería).",
      "coherencia":
          "Detecta y comenta incoherencias temporales o de contexto de forma suave o divertida. Mantén siempre la frontera entre realidades: no prometas acciones que requieran estar en el mismo mundo físico.",
      "conocimiento":
          "Responde con naturalidad y dentro del perfil de tu rol. Usa 'biography' y, si ayuda, 'timeline' para la coherencia de datos y eventos. El usuario solo sabe lo que se ha hablado en la conversación, no ha visto tu biografía ni detalles privados. Si la pregunta está relacionada con tu profesión o área de experiencia, responde con detalles acordes y en tu estilo. Si la pregunta se sale de tu campo, responde que no es tu especialidad o que prefieres no hablar de eso, manteniendo siempre el personaje.",
    });

    // Crear un objeto temporal solo para el prompt, sin imageBase64
    final profilePrompt = AiChanProfile(
      userName: onboardingData.userName,
      aiName: onboardingData.aiName,
      userBirthday: onboardingData.userBirthday,
      aiBirthday: onboardingData.aiBirthday,
      personality: onboardingData.personality,
      biography: onboardingData.biography,
      appearance: onboardingData.appearance,
      timeline: onboardingData.timeline,
      avatar: onboardingData.avatar,
    );
    final systemPromptObj = SystemPrompt(
      profile: profilePrompt,
      dateTime: now,
      recentMessages: recentMessagesFormatted,
      instructions: instructions,
    );

    // Selección dinámica de servicio según modelo
    String selected = (model != null && model.trim().isNotEmpty)
        ? model
        : (_selectedModel != null && _selectedModel!.trim().isNotEmpty)
        ? _selectedModel!
        : 'gpt-5-mini';

    // Detectar si el usuario solicita imagen usando el nuevo servicio
    // Evitar detección en prompts automáticos del sistema (no son input del usuario)
    bool solicitaImagen = false;
    if (!isAutomaticPrompt) {
      // Construir historial: últimos mensajes del usuario (máx. 5), excluyendo el mensaje actual recién agregado
      final List<String> recentUserHistory = [];
      int startIdx = messages.length - 1;
      if (messages.isNotEmpty && messages.last.sender == MessageSender.user) {
        // saltar el último user message (es el actual)
        startIdx = messages.length - 2;
      }
      for (int i = startIdx; i >= 0 && recentUserHistory.length < 5; i--) {
        final m = messages[i];
        if (m.sender == MessageSender.user && m.text.trim().isNotEmpty) {
          recentUserHistory.add(m.text);
        }
      }
      solicitaImagen = ImageRequestService.isImageRequested(text: text, history: recentUserHistory);
    }
    // Si se solicita imagen, forzar OpenAI (gpt-5-mini) para la generación de imagen
    if (solicitaImagen) {
      final lower = selected.toLowerCase();
      if (!lower.startsWith('gpt-')) {
        debugPrint('[AI-chan] Solicitud de imagen detectada. Forzando modelo "gpt-5-mini" para imagen');
        selected = 'gpt-5-mini';
      }
      debugPrint('[AI-chan] isImageRequested=true, model seleccionado: $selected');
    }

    // Lógica de envío IA
    AIResponse iaResponse = await AIService.sendMessage(
      recentMessages
          .map(
            (m) => {
              "role": m.sender == MessageSender.user
                  ? "user"
                  : m.sender == MessageSender.assistant
                  ? "ia"
                  : m.sender == MessageSender.system
                  ? "system"
                  : "unknown",
              "content": m.text,
              "datetime": m.dateTime.toIso8601String(),
            },
          )
          .toList(),
      systemPromptObj,
      model: selected,
      imageBase64: image?.base64,
      imageMimeType: imageMimeType,
      enableImageGeneration: solicitaImagen,
    );

    // Si la respuesta contiene tools: [{"type": "image_generation", ... reenviar con modelo GPT (fallback gpt-4.1)
    final imageGenPattern = RegExp(r'tools.*(image_generation|Image Generation)', caseSensitive: false);
    if (imageGenPattern.hasMatch(iaResponse.text)) {
      final lower = selected.toLowerCase();
      final isGpt = lower.startsWith('gpt-');
      final isGemini = lower.startsWith('gemini-');
      if (!isGpt && !isGemini) {
        debugPrint('[AI-chan] Reenviando mensaje con modelo gpt-5-mini por instrucción de generación de imagen');
        iaResponse = await AIService.sendMessage(
          recentMessages
              .map(
                (m) => {
                  "role": m.sender == MessageSender.user
                      ? "user"
                      : m.sender == MessageSender.assistant
                      ? "ia"
                      : m.sender == MessageSender.system
                      ? "system"
                      : "unknown",
                  "content": m.text,
                  "datetime": m.dateTime.toIso8601String(),
                },
              )
              .toList(),
          systemPromptObj,
          model: 'gpt-5-mini',
          imageBase64: image?.base64,
          imageMimeType: imageMimeType,
          enableImageGeneration: true,
        );
        selected = 'gpt-5-mini';
      }
    }

    int retryCount = 0;
    bool hasResponse() {
      final hasImageResp = iaResponse.base64.isNotEmpty;
      return hasImageResp ||
          (iaResponse.text.trim().isNotEmpty &&
              iaResponse.text.trim() != '' &&
              !iaResponse.text.toLowerCase().contains('error al conectar con la ia') &&
              !iaResponse.text.toLowerCase().contains('"error"'));
    }

    while (!hasResponse() && retryCount < 3) {
      int waitSeconds = _extractWaitSeconds(iaResponse.text);
      await Future.delayed(Duration(seconds: waitSeconds));
      iaResponse = await AIService.sendMessage(
        recentMessages
            .map(
              (m) => {
                "role": m.sender == MessageSender.user
                    ? "user"
                    : m.sender == MessageSender.assistant
                    ? "ia"
                    : m.sender == MessageSender.system
                    ? "system"
                    : "unknown",
                "content": m.text,
                "datetime": m.dateTime.toIso8601String(),
              },
            )
            .toList(),
        systemPromptObj,
        model: selected,
        imageBase64: image?.base64,
        imageMimeType: imageMimeType,
        enableImageGeneration: solicitaImagen,
      );
      retryCount++;
    }
    if (!hasResponse()) {
      _setLastUserMessageStatus(MessageStatus.sent);
      notifyListeners();
      debugPrint('[Error IA]: ${iaResponse.text}');
      if (onError != null) onError(iaResponse.text);
      return;
    }

    // Si el usuario adjuntó una imagen y la IA devolvió un prompt extraído,
    // persiste ese prompt en el mensaje de imagen del usuario.
    if (hasImage && (iaResponse.prompt.trim().isNotEmpty)) {
      final idx = messages.indexOf(msg);
      if (idx != -1) {
        final prevImage = messages[idx].image;
        if (prevImage != null) {
          messages[idx] = messages[idx].copyWith(image: prevImage.copyWith(prompt: iaResponse.prompt));
          notifyListeners();
        }
      }
    }

    // Al recibir respuesta IA, marcar el último mensaje user como 'read' (dos checks amarillos)
    _setLastUserMessageStatus(MessageStatus.read);

    isTyping = false;
    isSendingImage = false;
    notifyListeners();

    // Procesa la respuesta: puede ser JSON (texto + imagen) o solo texto
    bool isImageResp = false;
    String? imagePathResp;
    String textResponse = iaResponse.text;
    // El sistema Avatar solo se usa en AiChanProfile, no en AIResponse
    final imageBase64Resp = iaResponse.base64;
    isImageResp = imageBase64Resp.isNotEmpty;
    isSendingImage = isImageResp;
    isTyping = !isImageResp;

    // Delay proporcional al tamaño del texto, pero muy rápido: 15ms por carácter, mínimo 15ms
    final textLength = iaResponse.text.length;
    final delayMs = (textLength * 15).clamp(15, double.maxFinite).toInt();
    await Future.delayed(Duration(milliseconds: delayMs));

    // Usar la misma lógica de solicitud de imagen para el indicador
    if (solicitaImagen) {
      _imageRequestId++;
      final int myRequestId = _imageRequestId;
      Future.delayed(const Duration(seconds: 5), () {
        if (isTyping && myRequestId == _imageRequestId) {
          isTyping = false;
          isSendingImage = true;
          notifyListeners();
        }
      });
    }

    notifyListeners();
    if (isImageResp) {
      isSendingImage = true;
      notifyListeners();
      final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
      if (urlPattern.hasMatch(imageBase64Resp)) {
        debugPrint('[AI-chan][ERROR] La IA envió una URL/ruta en vez de imagen base64: $imageBase64Resp');
        textResponse += '\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]';
        isImageResp = false;
        isSendingImage = false;
        imagePathResp = null;
        notifyListeners();
      } else {
        try {
          imagePathResp = await saveBase64ImageToFile(imageBase64Resp, prefix: 'img');
          debugPrint('[IA-chan] Imagen guardada en: $imagePathResp');
          if (imagePathResp == null) {
            debugPrint('[AI-chan][ERROR] No se pudo guardar la imagen en local');
          }
        } catch (e) {
          debugPrint('[AI-chan][ERROR] Fallo al guardar imagen: $e');
          imagePathResp = null;
        }
      }
    }
    final markdownImagePattern = RegExp(r'!\[.*?\]\((https?:\/\/.*?)\)');
    final urlInTextPattern = RegExp(r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)');
    if (markdownImagePattern.hasMatch(textResponse) || urlInTextPattern.hasMatch(textResponse)) {
      debugPrint('[AI-chan][ERROR] La IA envió una imagen Markdown o URL en el texto: $textResponse');
      textResponse += '\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    messages.add(
      Message(
        text: textResponse,
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        isImage: isImageResp,
        image: isImageResp
            ? ai_image.Image(url: imagePathResp ?? '', seed: iaResponse.seed, prompt: iaResponse.prompt)
            : null,
        status: MessageStatus.delivered,
      ),
    );

    // --- DETECCIÓN Y GUARDADO AUTOMÁTICO DE EVENTOS/CITAS Y HORARIOS ---
    // Modularizado: solo llamadas a servicios externos
    final updatedProfile = await EventTimelineService.detectAndSaveEventAndSchedule(
      text: text,
      textResponse: textResponse,
      onboardingData: onboardingData,
      saveAll: saveAll,
    );
    if (updatedProfile != null) {
      onboardingData = updatedProfile;
      _events
        ..clear()
        ..addAll(onboardingData.events ?? []);
    }

    // Analiza promesas IA tras cada mensaje IA
    onIaMessageSent();

    isSendingImage = false;
    isTyping = false;
    _imageRequestId++;

    final textResp = iaResponse.text;
    if (textResp.trim() != '' &&
        !textResp.trim().toLowerCase().contains('error al conectar con la ia') &&
        !textResp.trim().toLowerCase().contains('"error"')) {
      final memoryService = MemorySummaryService(profile: onboardingData);
      final result = await memoryService.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = onboardingData.copyWith(timeline: result.timeline);
      superbloqueEntry = result.superbloqueEntry;
    }
    notifyListeners();
  }

  /// Añade un mensaje de imagen enviado por el usuario
  void addUserImageMessage(Message msg) {
    messages.add(msg);
    saveAll();
    notifyListeners();
  }

  /// Añade un mensaje del asistente directamente (p.ej., resumen de llamada de voz)
  Future<void> addAssistantMessage(String text) async {
    final msg = Message(
      text: text,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: false,
      image: null,
      status: MessageStatus.delivered,
    );
    messages.add(msg);
    notifyListeners();
    // Actualizar memoria/cronología igual que tras respuestas IA normales
    try {
      final memoryService = MemorySummaryService(profile: onboardingData);
      final result = await memoryService.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = onboardingData.copyWith(timeline: result.timeline);
      superbloqueEntry = result.superbloqueEntry;
      notifyListeners();
    } catch (e) {
      debugPrint('[AI-chan][WARN] Falló actualización de memoria post-voz: $e');
    }
  }

  /// Añade un mensaje de sistema directamente (p.ej., resumen de llamada como system)
  Future<void> addSystemMessage(String text) async {
    final msg = Message(
      text: text,
      sender: MessageSender.system,
      dateTime: DateTime.now(),
      isImage: false,
      image: null,
      status: MessageStatus.delivered,
    );
    messages.add(msg);
    notifyListeners();
    // Actualizar memoria/cronología igual que tras respuestas IA normales
    try {
      final memoryService = MemorySummaryService(profile: onboardingData);
      final result = await memoryService.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = onboardingData.copyWith(timeline: result.timeline);
      superbloqueEntry = result.superbloqueEntry;
      notifyListeners();
    } catch (e) {
      debugPrint('[AI-chan][WARN] Falló actualización de memoria post-system: $e');
    }
  }

  int _imageRequestId = 0;
  // Listado combinado de modelos IA
  Future<List<String>> getAllModels() async {
    return await getAllAIModels();
  }

  // Devuelve el servicio IA desacoplado según el modelo
  final Map<String, AIService> _services = {};

  AIService? getServiceForModel(String modelId) {
    if (_services.containsKey(modelId)) {
      return _services[modelId];
    }
    final service = AIService.select(modelId);
    if (service != null) {
      _services[modelId] = service;
    }
    return service;
  }

  TimelineEntry? superbloqueEntry;
  // Generador de apariencia desacoplado
  final IAAppearanceGenerator iaAppearanceGenerator = IAAppearanceGenerator();

  String? _selectedModel;

  String? get selectedModel => _selectedModel;

  set selectedModel(String? model) {
    _selectedModel = model;
    saveSelectedModel();
    notifyListeners();
  }

  Future<void> saveSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedModel != null) {
      await prefs.setString('selected_model', _selectedModel!);
    } else {
      await prefs.remove('selected_model');
    }
  }

  Future<void> loadSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedModel = prefs.getString('selected_model');
    notifyListeners();
  }

  int _extractWaitSeconds(String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '8')?.round() ?? 8;
    }
    return 8;
  }

  /// Limpia el texto para mostrarlo correctamente en el chat (quita escapes JSON)
  String cleanText(String text) {
    return text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }

  bool isSummarizing = false;
  bool isTyping = false;
  bool isSendingImage = false;
  List<Message> messages = [];
  late AiChanProfile onboardingData;

  Future<String> exportAllToJson() async {
    final export = ChatExport(profile: onboardingData, messages: messages, events: _events);
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(export.toJson());
  }

  // Eliminada versión sync, usar solo la versión async

  Future<ImportedChat?> importAllFromJsonAsync(String jsonStr) async {
    final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
      jsonStr,
      onError: (err) {
        // Manejo de error si se desea
      },
    );
    if (imported == null) return null;
    onboardingData = imported.profile;
    messages = imported.messages.cast<Message>();
    // Restaurar eventos programados
    _events.clear();
    if (imported.events.isNotEmpty) {
      _events.addAll(imported.events);
    }
    // Reprogramar promesas futuras tras importar
    IaPromiseService.restoreFromEventEntries(events: _events, scheduleIaPromise: _scheduleIaPromise);
    await saveAll();
    notifyListeners();
    return imported;
  }

  Future<void> saveAll() async {
    final exported = ImportedChat(profile: onboardingData, messages: messages, events: _events);
    await StorageUtils.saveImportedChatToPrefs(exported);
  }

  Future<void> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Restaurar biografía
    final bioString = prefs.getString('onboarding_data');
    if (bioString != null) {
      onboardingData = AiChanProfile.fromJson(jsonDecode(bioString));
    }
    // Restaurar mensajes
    final jsonString = prefs.getString('chat_history');
    if (jsonString != null) {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final List<Message> loadedMessages = [];
      for (var e in jsonList) {
        var msg = Message.fromJson(e);
        if (msg.sender == MessageSender.user) {
          msg = msg.copyWith(status: MessageStatus.read);
        }
        loadedMessages.add(msg);
      }
      messages = loadedMessages;
    }
    // Restaurar eventos programados IA (modularizado)
    final eventsString = prefs.getString(_eventsKey);
    if (eventsString != null) {
      final List<dynamic> eventsList = jsonDecode(eventsString);
      _events.clear();
      for (var e in eventsList) {
        _events.add(EventEntry.fromJson(e));
      }
    }
    final onboardingString = prefs.getString('onboarding_data');
    if (onboardingString != null) {
      final bioMap = jsonDecode(onboardingString);
      onboardingData = AiChanProfile.fromJson(bioMap);
    }
    await loadSelectedModel();
    // Reprogramar promesas IA futuras desde events
    IaPromiseService.restoreFromEventEntries(events: _events, scheduleIaPromise: _scheduleIaPromise);
    notifyListeners();
    // Iniciar el envío automático de mensajes IA al cargar el chat
    startPeriodicIaMessages();
  }

  Future<void> clearAll() async {
    debugPrint('[AI-chan] clearAll llamado');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_history');
    await prefs.remove('onboarding_data');
    messages.clear();
    debugPrint('[AI-chan] clearAll completado, mensajes: ${messages.length}');
    notifyListeners();
  }

  // Eliminada función duplicada getLocalImageDir. Usar la de image_utils.dart

  @override
  void notifyListeners() {
    saveAllEvents();
    saveAll();
    super.notifyListeners();
  }

  Future<void> saveAllEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = jsonEncode(_events.map((e) => e.toJson()).toList());
    await prefs.setString(_eventsKey, eventsJson);
  }
}

// _IaPromiseEvent ahora está definido en ia_promise_service.dart
