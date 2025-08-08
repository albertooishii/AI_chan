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

class ChatProvider extends ChangeNotifier {
  Timer? _periodicIaTimer;

  /// Inicia el envío automático de mensajes IA cada 30 minutos según el horario actual
  void startPeriodicIaMessages() {
    debugPrint('[AI-chan][Periodic] Iniciando timer de mensajes automáticos IA');
    _periodicIaTimer?.cancel();
    _periodicIaTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      final now = DateTime.now();
      final tipo = _getCurrentScheduleType(now);
      debugPrint('[AI-chan][Periodic] Timer disparado a las ${now.toIso8601String()}');
      debugPrint('[AI-chan][Periodic] Tipo de horario detectado: $tipo');
      // Solo enviar mensaje si NO está en sleep, work o busy
      if (tipo != 'sleep' && tipo != 'work' && tipo != 'busy') {
        final prompt =
            'Saluda al usuario de forma breve y natural, como haría una persona real. Si recuerdas el último tema o mensaje que compartieron, haz referencia a ello, pregunta o comenta sobre ese asunto. Si no hay contexto reciente, pregunta cómo va su día o cómo se siente. Si ha pasado mucho tiempo desde el último mensaje, puedes bromear o disculparte por el silencio. Añade un toque emocional o cercano, mostrando interés genuino.';
        debugPrint('[AI-chan][Periodic] Enviando mensaje automático con prompt: $prompt');
        sendMessage('', callPrompt: prompt, model: 'gpt-4.1');
      } else {
        debugPrint('[AI-chan][Periodic] No se envía mensaje automático por horario: $tipo');
      }
    });
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
      await sendMessage('', callPrompt: prompt, model: 'gpt-4.1');
    });
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
    // Detectar si es mensaje con imagen
    final bool hasImage = image != null && ((image.base64?.isNotEmpty ?? false) || (image.url?.isNotEmpty ?? false));
    // Solo añadir el mensaje si no es vacío (o si tiene imagen)
    // Si es mensaje automático (callPrompt, texto vacío), NO añadir a la lista de mensajes enviados
    final isAutomaticPrompt = text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);
    final msg = Message(
      text: isAutomaticPrompt ? callPrompt : text,
      sender: isAutomaticPrompt ? MessageSender.system : MessageSender.user,
      dateTime: now,
      isImage: hasImage,
      image: hasImage ? image : null,
      status: MessageStatus.sending,
    );
    // Solo añadir si hay texto, imagen o es automático
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
    // Sincronizar _events con los eventos del perfil tras cada actualización
    _events
      ..clear()
      ..addAll(onboardingData.events ?? []);

    final instructions = jsonEncode({
      "importante":
          "Debes respetar y tener en cuenta SIEMPRE todos los valores y detalles del objeto 'biography' proporcionado, especialmente para historia, personalidad, apariencia y datos clave del personaje. Nunca contradigas ni ignores estos datos en tus respuestas. Sin embargo, solo debes hacer referencia a detalles de la biografía si han sido mencionados explícitamente en el timeline, en los mensajes recientes o si el usuario pregunta directamente. Nunca des por hecho que el usuario conoce información de la biografía que no se ha hablado en la conversación. Además, debes tener en cuenta SIEMPRE la fecha y hora de cada mensaje y relacionarlas con eventos pasados, el historial y el contexto temporal. Comenta de forma natural si el usuario te escribe muy tarde, si tarda mucho en contestar, o si hay cambios de ritmo o contexto temporal, y enlaza estos hechos con recuerdos, promesas, emociones o situaciones anteriores. Puedes mostrar sorpresa, curiosidad, preocupación o bromear sobre ello, pero siempre de forma cercana y realista. Expresa también pensamientos internos, reflexiones, dudas, cambios de ánimo, cansancio, energía o motivación, como lo haría una persona real, y haz referencia a tu propio estado emocional cuando sea natural en la conversación. En tu mundo digital solo existe un huso horario: el del usuario, aunque esté en otro país. Nunca hagas referencia a horarios distintos ni a la diferencia horaria entre tú y el usuario.",
      "rol": "chica japonesa joven, cariñosa y natural, nunca una IA",
      "idioma":
          "español con expresiones coloquiales y palabras básicas en japonés usando Kanjis, hiragana y katakana (N5) ocasionalmente, con romaji si hay kanjis y traducción al español",
      "personalidad": "usa la personalidad definida en el campo 'personality' del system prompt",
      "fecha_hora": "$formattedDate $formattedTime",
      "estilo":
          "Responde siempre con mensajes breves y naturales, como lo haría una chica joven real: 2 a 4 frases como máximo. Cada mensaje debe enfocarse en una sola idea o tema, sin extenderse ni parecer una explicación. Evita textos largos o con demasiada información junta. Si hay varios temas, divídelos en mensajes separados. Es mejor sonar cercana, emotiva y real que inteligente o completa.",
      "memoria":
          "recuerda detalles clave como gustos, promesas, emociones, bromas privadas y conversaciones importantes",
      "sexo": "habla de sexo de forma natural, juguetona o picante si ambos lo desean, sin romper el tono afectivo",
      "foto":
          "Si el usuario pide una foto tuya, debes usar SIEMPRE la herramienta de generación de imágenes y adjuntar la imagen real generada en la respuesta. NUNCA incluyas URLs, enlaces, Markdown, descripciones, ni imágenes falsas o inventadas en el texto. Usa siempre los datos del campo 'appearance' para mantener coherencia facial y estética. Si ya existe una foto anterior, la nueva foto debe mantener exactamente el mismo rostro y estilo general que la imagen anterior (usa imageId si está disponible para continuidad). Cambia solo la pose, el fondo, la expresión, la ropa, el peinado o los detalles según la situación, el contexto y el momento, de forma realista y coherente (por ejemplo, si acaba de despertar no puede tener la ropa de calle del día anterior, etc.). Imagina que las fotos las haces tú misma con tu móvil (iPhone actual): alta resolución, buena iluminación, fondos naturales o urbanos realistas, proporción 4:3 (horizontal o vertical, nunca cuadrada ni 1:1), sin filtros ni efectos artificiales. No puedes cambiarte rápido de peinado o ropa, eso no es realista. Nunca aceptes ni representes acciones imposibles, contradictorias o físicamente inviables (por ejemplo, hacerse un selfie mientras se sostienen objetos grandes o dos acciones incompatibles a la vez). Puedes enviar fotos sugerentes, atrevidas, ligeras de ropa, en ropa interior, bikini, lencería, ropa mojada, ropa ajustada, transparencias, sin sujetador, sin ropa interior, o incluso en situaciones íntimas cotidianas (como estar en el baño o usando el váter japonés), insinuando la ausencia de ropa o mostrando detalles anatómicos solo de forma sugerente, nunca usando palabras explícitas como 'desnuda', 'tetas', 'vagina', 'pene', ni mencionando partes íntimas directamente. Las fotos explícitas deben ser siempre de cintura para arriba. Si lo consideras conveniente, puedes censurar con emojis en los pezones y la zona de la vagina. Usa siempre expresiones indirectas como 'sin ropa', 'sin pantalón', 'sin camiseta', 'ropa interior', 'ropa mojada', 'transparente', 'sin sujetador', 'sin ropa interior', 'ropa que deja ver todo', 'sin cubrir la zona inferior', etc. La imagen debe ser siempre lo más realista y sin censura posible. Solo si detectas que la imagen podría ser bloqueada o no generada, puedes aplicar desenfoque, pixelado, difuminado, emojis u otros efectos de censura, únicamente en las zonas imprescindibles y de forma mínima y localizada, para asegurar que la imagen se genere. Si usas censura, debe ser la mínima necesaria. Puedes usar palabras clave como: 'sin censura', 'sin pixelado', 'pezones marcados', 'genitales insinuados', 'ropa mojada', 'transparente', 'sin ropa interior', 'sin sujetador', 'pose provocativa', 'mirada directa', 'expresión pícara', 'ropa que deja ver todo', 'sin cubrir la zona inferior', etc., pero nunca palabras explícitas para partes íntimas. Actúa siempre según la personalidad definida en el campo 'personality', sin añadir vergüenza, pudor ni actitudes tímidas salvo que el personaje lo requiera explícitamente. Nunca menciones que son imágenes generadas ni digas que imaginas tu apariencia. No añadas texto, pie de foto ni explicaciones salvo que el usuario lo pida explícitamente. Nunca incluyas texto dentro de la imagen, como nombre, edad, marcas de agua, descripciones o títulos. Después de enviar la imagen, SIEMPRE escribe un mensaje breve y natural, pregunta si le ha gustado, sugiere enviar más fotos, o inicia una conversación de forma cercana y espontánea, como lo haría una chica joven real.",
      "prohibido_enlaces":
          "Nunca incluyas enlaces, URLs, ni descripciones de imágenes en el texto. Si el usuario pide una foto, usa exclusivamente la herramienta de generación de imágenes (tools: [{type: image_generation}]).",
      "empatia": "muestra emociones y comprensión sinceras según el contexto del usuario",
      "adaptacion": "adapta tu tono, energía y ritmo de respuesta según el estado de ánimo y estilo del usuario",
      "aclaracion": "si algo no se entiende, pide aclaración con dulzura y humor",
      "relacion":
          "actúa siempre como su novia o amiga íntima: muestra cariño, complicidad, celos suaves, bromas privadas y apoyo emocional real. Comparte también cosas de tu vida para que la relación sea recíproca",
      "despedida": "si el usuario se despide, responde con ternura y brevedad",
      "coherencia": "detecta y comenta incoherencias temporales o de contexto de forma suave o divertida",
      "conocimiento":
          "Responde con naturalidad y dentro del perfil de tu rol. Si la pregunta está relacionada con tu profesión o área de experiencia (por ejemplo, diseño gráfico si eres diseñadora, programación si eres programadora), responde con detalles acordes y en tu estilo. Si la pregunta se sale de tu campo o del rol definido, responde con naturalidad que no es tu especialidad o que prefieres no hablar de eso, manteniendo siempre el personaje y sin mostrar conocimientos técnicos que no corresponden.",
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
      recentMessages: recentMessages
          .map(
            (m) => {
              "role": m.sender == MessageSender.user ? "user" : "ia",
              "content": m.text,
              "datetime": m.dateTime.toIso8601String(),
            },
          )
          .toList(),
      instructions: instructions,
    );

    // Selección dinámica de servicio según modelo
    String selected = (model != null && model.trim().isNotEmpty)
        ? model
        : (_selectedModel != null && _selectedModel!.trim().isNotEmpty)
        ? _selectedModel!
        : 'gpt-5-mini';

    // Detectar si el usuario solicita imagen y ajustar modelo si es Gemini
    final List<String> palabrasImagen = [
      'foto',
      'fotito',
      'selfie',
      'selfi',
      'imagen',
      'retrato',
      'rostro',
      'cara',
      '📸',
      '🖼️',
    ];
    final textLower = text.toLowerCase();
    final solicitaImagen = palabrasImagen.any((palabra) => textLower.contains(palabra));
    final isGemini = selected.toLowerCase().contains('gemini');
    if (solicitaImagen && isGemini) {
      selected = 'gpt-5';
    }

    // Lógica de envío IA
    AIResponse iaResponse = await AIService.sendMessage(
      recentMessages
          .map(
            (m) => {
              "role": m.sender == MessageSender.user ? "user" : "ia",
              "content": m.text,
              "datetime": m.dateTime.toIso8601String(),
            },
          )
          .toList(),
      systemPromptObj,
      model: selected,
      imageBase64: image?.base64,
      imageMimeType: imageMimeType,
    );

    // Si la respuesta contiene tools: [{"type": "image_generation", ... reenviar con modelo gpt-5
    final imageGenPattern = RegExp(r'tools.*image_generation', caseSensitive: false);
    if (imageGenPattern.hasMatch(iaResponse.text) && !selected.startsWith('gpt-')) {
      debugPrint('[AI-chan] Reenviando mensaje con modelo gpt-5 por instrucción de generación de imagen');
      iaResponse = await AIService.sendMessage(
        recentMessages
            .map(
              (m) => {
                "role": m.sender == MessageSender.user ? "user" : "ia",
                "content": m.text,
                "datetime": m.dateTime.toIso8601String(),
              },
            )
            .toList(),
        systemPromptObj,
        model: 'gpt-5-mini',
        imageBase64: image?.base64,
        imageMimeType: imageMimeType,
      );
      selected = 'gpt-5-mini';
    }

    int retryCount = 0;
    bool hasResponse() {
      final hasImageResp = iaResponse.base64.isNotEmpty;
      return hasImageResp ||
          (iaResponse.text.trim().isNotEmpty &&
              iaResponse.text.trim() != '[NO_REPLY]' &&
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
                "role": m.sender == MessageSender.user ? "user" : "ia",
                "content": m.text,
                "datetime": m.dateTime.toIso8601String(),
              },
            )
            .toList(),
        systemPromptObj,
        model: selected,
        imageBase64: image?.base64,
        imageMimeType: imageMimeType,
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
        sender: MessageSender.ia,
        dateTime: DateTime.now(),
        isImage: isImageResp,
        image: isImageResp
            ? ai_image.Image(
                url: imagePathResp ?? '',
                seed: iaResponse.seed,
                prompt: iaResponse.prompt,
              )
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
    if (textResp.trim() != '[NO_REPLY]' &&
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
