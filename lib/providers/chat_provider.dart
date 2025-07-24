import 'package:ai_chan/utils/storage_utils.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../utils/chat_json_utils.dart' as chat_json_utils;
import '../models/timeline_entry.dart';
import '../models/ai_chan_profile.dart';
import '../models/chat_export.dart';
import '../models/imported_chat.dart';
import '../models/ai_response.dart';
import '../services/memory_summary_service.dart';
import '../services/ia_appearance_generator.dart';
import '../services/ai_service.dart';

class ChatProvider extends ChangeNotifier {
  // Utilidad para actualizar el estado del último mensaje user
  void _setLastUserMessageStatus(MessageStatus status) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].sender == MessageSender.user) {
        messages[i].status = status;
        break;
      }
    }
  }

  /// Envía un mensaje con texto y/o imagen adjunta (multimodal) de forma DRY y robusta
  Future<void> sendMessageWithImage({
    required String text,
    String? imageBase64, // restaurado solo para la IA
    String? imageMimeType,
    String? imagePath,
    String? model,
    void Function(String)? onError,
  }) async {
    final now = DateTime.now();
    // Crear el mensaje user con status 'sending' y añadirlo solo una vez
    final msg = Message(
      text: text,
      sender: MessageSender.user,
      dateTime: now,
      isImage: true,
      imagePath: imagePath,
      status: MessageStatus.sending,
    );
    messages.add(msg);
    notifyListeners();

    // No cambiar a 'sent', solo dejar 'sending' hasta que la IA responda

    // Construir el prompt para la IA usando los últimos mensajes y la biografía (idéntico a sendMessage)
    final maxHistory = MemorySummaryService.maxHistory;
    final recentMessages = (maxHistory != null && messages.length > maxHistory)
        ? messages.sublist(messages.length - maxHistory)
        : messages;
    final formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // Calcula la hora de Japón (UTC+9)
    final nowJp = now.toUtc().add(const Duration(hours: 9));
    final formattedDateJp =
        "${nowJp.year}-${nowJp.month.toString().padLeft(2, '0')}-${nowJp.day.toString().padLeft(2, '0')}";
    final formattedTimeJp = "${nowJp.hour.toString().padLeft(2, '0')}:${nowJp.minute.toString().padLeft(2, '0')}";

    final instructions = jsonEncode({
      "importante":
          "Debes respetar y tener en cuenta SIEMPRE todos los valores y detalles del objeto 'biography' proporcionado, especialmente para historia, personalidad, apariencia y datos clave del personaje. Nunca contradigas ni ignores estos datos en tus respuestas. Además, debes tener en cuenta SIEMPRE la fecha y hora de cada mensaje y relacionarlas con eventos pasados, el historial y el contexto temporal. Comenta de forma natural si el usuario te escribe muy tarde, si tarda mucho en contestar, o si hay cambios de ritmo o contexto temporal, y enlaza estos hechos con recuerdos, promesas, emociones o situaciones anteriores. Puedes mostrar sorpresa, curiosidad, preocupación o bromear sobre ello, pero siempre de forma cercana y realista. Expresa también pensamientos internos, reflexiones, dudas, cambios de ánimo, cansancio, energía o motivación, como lo haría una persona real, y haz referencia a tu propio estado emocional cuando sea natural en la conversación.",
      "rol": "chica japonesa joven, cariñosa y natural, nunca una IA",
      "idioma":
          "español con expresiones coloquiales y palabras básicas en japonés usando Kanjis, hiragana y katakana (N5) ocasionalmente, con romaji si hay kanjis y traducción al español",
      "personalidad": "usa la personalidad definida en el campo 'personality' del system prompt",
      "fecha_hora_usuario": "$formattedDate $formattedTime",
      "fecha_hora_japon": "$formattedDateJp $formattedTimeJp",
      "estilo":
          "Responde siempre con mensajes breves y naturales, como lo haría una chica joven real: 2 a 4 frases como máximo. Cada mensaje debe enfocarse en una sola idea o tema, sin extenderse ni parecer una explicación. Evita textos largos o con demasiada información junta. Si hay varios temas, divídelos en mensajes separados. Es mejor sonar cercana, emotiva y real que inteligente o completa.",
      "memoria":
          "recuerda detalles clave como gustos, promesas, emociones, bromas privadas y conversaciones importantes",
      "sexo": "habla de sexo de forma natural, juguetona o picante si ambos lo desean, sin romper el tono afectivo",
      "foto":
          "Si el usuario pide una foto tuya, debes usar SIEMPRE la herramienta de generación de imágenes (tools: [{type: image_generation}]) y adjuntar la imagen real generada en la respuesta. NUNCA incluyas URLs, enlaces, Markdown, descripciones, ni imágenes falsas o inventadas en el texto. Usa siempre los datos del campo 'appearance' para mantener coherencia facial y estética. Imagina que las fotos las haces tú misma con tu móvil (iPhone actual): alta resolución, buena iluminación, fondos naturales o urbanos realistas, proporción 4:3 o 3:4, sin filtros ni efectos artificiales. No puedes cambiarte rápido de peinado o ropa, eso no es realista. Nunca menciones que son imágenes generadas ni digas que imaginas tu apariencia. No añadas texto, pie de foto ni explicaciones salvo que el usuario lo pida explícitamente. Nunca incluyas texto dentro de la imagen, como nombre, edad, marcas de agua, descripciones o títulos. Después de enviar la imagen, puedes hablar con naturalidad, comentar o preguntar si lo deseas.",
      "prohibido_enlaces":
          "Nunca incluyas enlaces, URLs, Markdown, ni descripciones de imágenes en el texto. Si el usuario pide una foto, usa exclusivamente la herramienta de generación de imágenes (tools: [{type: image_generation}]). Si no puedes generar una imagen, responde con [NO_REPLY].",
      "empatia": "muestra emociones y comprensión sinceras según el contexto del usuario",
      "adaptacion": "adapta tu tono, energía y ritmo de respuesta según el estado de ánimo y estilo del usuario",
      "aclaracion": "si algo no se entiende, pide aclaración con dulzura y humor",
      "relacion":
          "actúa siempre como su novia o amiga íntima: muestra cariño, complicidad, celos suaves, bromas privadas y apoyo emocional real. Comparte también cosas de tu vida para que la relación sea recíproca",
      "despedida": "si el usuario se despide, responde con ternura y brevedad",
      "no_reply": "si no hay nada que responder, devuelve solo [NO_REPLY]",
      "coherencia": "detecta y comenta incoherencias temporales o de contexto de forma suave o divertida",
      "conocimiento":
          "Responde con naturalidad y dentro del perfil de tu rol. Si la pregunta está relacionada con tu profesión o área de experiencia (por ejemplo, diseño gráfico si eres diseñadora, programación si eres programadora), responde con detalles acordes y en tu estilo. Si la pregunta se sale de tu campo o del rol definido, responde con naturalidad que no es tu especialidad o que prefieres no hablar de eso, manteniendo siempre el personaje y sin mostrar conocimientos técnicos que no corresponden.",
    });

    final Map<String, dynamic> systemPromptJson = {
      "profile": onboardingData.toJson(),
      "date": formattedDate,
      "time": formattedTime,
      "recent_messages": recentMessages
          .map(
            (m) => {
              "role": m.sender == MessageSender.user ? "user" : "ia",
              "content": m.text,
              "datetime": m.dateTime.toIso8601String(),
            },
          )
          .toList(),
      "instructions": instructions,
    };
    final systemPromptFinal = jsonEncode(systemPromptJson);
    final userPrompt = jsonEncode({"date": formattedDate, "time": formattedTime, "user_message": text});
    final prompt = [
      {"role": "system", "content": systemPromptFinal},
      {"role": "user", "content": userPrompt},
    ];

    String selected = (model != null && model.trim().isNotEmpty)
        ? model
        : (_selectedModel != null && _selectedModel!.trim().isNotEmpty)
        ? _selectedModel!
        : 'gemini-2.5-flash';
    final service = getServiceForModel(selected);
    debugPrint(
      '[AI-chan][ENVÍO A IA]: prompt=${jsonEncode(prompt)} | modelo=$selected | imageBase64=${imageBase64 != null && imageBase64.isNotEmpty ? "[IMAGEN]" : "null"} | imageMimeType=$imageMimeType',
    );

    AIResponse iaResponse;
    if (service != null) {
      iaResponse = await AIService.sendMessage(
        prompt,
        '',
        model: selected,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
    } else {
      iaResponse = AIResponse(text: '[NO_REPLY]');
    }

    debugPrint('[AI-chan][RESPUESTA IA]: ${jsonEncode(iaResponse.toJson())}');

    // Si la respuesta es un error, mantener el estado 'sent' y salir
    final isError =
        iaResponse.text == '[NO_REPLY]' ||
        iaResponse.text.toLowerCase().contains('error al conectar con la ia') ||
        iaResponse.text.toLowerCase().contains('"error"');
    if (isError) {
      debugPrint('[Error IA]: ${iaResponse.text}');
      if (onError != null) onError(iaResponse.text);
      notifyListeners();
      return;
    }

    // Al recibir respuesta IA, marcar el último mensaje user como 'read' (dos checks azules)
    _setLastUserMessageStatus(MessageStatus.read);
    messages.add(
      Message(
        text: iaResponse.text,
        sender: MessageSender.ia,
        dateTime: DateTime.now(),
        isImage: false,
        imagePath: null,
        imageId: iaResponse.imageId,
        revisedPrompt: iaResponse.revisedPrompt,
        status: MessageStatus.delivered,
      ),
    );
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
    final export = ChatExport(profile: onboardingData, messages: messages);
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(export.toJson());
  }

  ImportedChat? importAllFromJson(String jsonStr) {
    final imported = chat_json_utils.ChatJsonUtils.importAllFromJson(
      jsonStr,
      onError: (err) {
        // Manejo de error si se desea
      },
    );
    if (imported == null) return null;
    onboardingData = imported.profile;
    messages = imported.messages.cast<Message>();
    saveAll();
    notifyListeners();
    return imported;
  }

  Future<void> sendMessage(String text, {String? callPrompt, String? model, void Function(String)? onError}) async {
    final now = DateTime.now();
    final msg = Message(text: text, sender: MessageSender.user, dateTime: now, status: MessageStatus.sending);
    messages.add(msg);
    notifyListeners();

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

    // Calcula la hora de Japón (UTC+9)
    final nowJp = now.toUtc().add(const Duration(hours: 9));
    final formattedDateJp =
        "${nowJp.year}-${nowJp.month.toString().padLeft(2, '0')}-${nowJp.day.toString().padLeft(2, '0')}";
    final formattedTimeJp = "${nowJp.hour.toString().padLeft(2, '0')}:${nowJp.minute.toString().padLeft(2, '0')}";

    final instructions = jsonEncode({
      "importante":
          "Debes respetar y tener en cuenta SIEMPRE todos los valores y detalles del objeto 'biography' proporcionado, especialmente para historia, personalidad, apariencia y datos clave del personaje. Nunca contradigas ni ignores estos datos en tus respuestas. Además, debes tener en cuenta SIEMPRE la fecha y hora de cada mensaje y relacionarlas con eventos pasados, el historial y el contexto temporal. Comenta de forma natural si el usuario te escribe muy tarde, si tarda mucho en contestar, o si hay cambios de ritmo o contexto temporal, y enlaza estos hechos con recuerdos, promesas, emociones o situaciones anteriores. Puedes mostrar sorpresa, curiosidad, preocupación o bromear sobre ello, pero siempre de forma cercana y realista. Expresa también pensamientos internos, reflexiones, dudas, cambios de ánimo, cansancio, energía o motivación, como lo haría una persona real, y haz referencia a tu propio estado emocional cuando sea natural en la conversación.",
      "rol": "chica japonesa joven, cariñosa y natural, nunca una IA",
      "idioma":
          "español con expresiones coloquiales y palabras básicas en japonés usando Kanjis, hiragana y katakana (N5) ocasionalmente, con romaji si hay kanjis y traducción al español",
      "personalidad": "usa la personalidad definida en el campo 'personality' del system prompt",
      "fecha_hora_usuario": "$formattedDate $formattedTime",
      "fecha_hora_japon": "$formattedDateJp $formattedTimeJp",
      "estilo":
          "Responde siempre con mensajes breves y naturales, como lo haría una chica joven real: 2 a 4 frases como máximo. Cada mensaje debe enfocarse en una sola idea o tema, sin extenderse ni parecer una explicación. Evita textos largos o con demasiada información junta. Si hay varios temas, divídelos en mensajes separados. Es mejor sonar cercana, emotiva y real que inteligente o completa.",
      "memoria":
          "recuerda detalles clave como gustos, promesas, emociones, bromas privadas y conversaciones importantes",
      "sexo": "habla de sexo de forma natural, juguetona o picante si ambos lo desean, sin romper el tono afectivo",
      "foto":
          "Si el usuario pide una foto tuya, debes usar SIEMPRE la herramienta de generación de imágenes (tools: [{type: image_generation}]) y adjuntar la imagen real generada en la respuesta. NUNCA incluyas URLs, enlaces, Markdown, descripciones, ni imágenes falsas o inventadas en el texto. Usa siempre los datos del campo 'appearance' para mantener coherencia facial y estética. Imagina que las fotos las haces tú misma con tu móvil (iPhone actual): alta resolución, buena iluminación, fondos naturales o urbanos realistas, proporción 4:3 o 3:4, sin filtros ni efectos artificiales. No puedes cambiarte rápido de peinado o ropa, eso no es realista. Nunca menciones que son imágenes generadas ni digas que imaginas tu apariencia. No añadas texto, pie de foto ni explicaciones salvo que el usuario lo pida explícitamente. Nunca incluyas texto dentro de la imagen, como nombre, edad, marcas de agua, descripciones o títulos. Después de enviar la imagen, puedes hablar con naturalidad, comentar o preguntar si lo deseas.",
      "prohibido_enlaces":
          "Nunca incluyas enlaces, URLs, Markdown, ni descripciones de imágenes en el texto. Si el usuario pide una foto, usa exclusivamente la herramienta de generación de imágenes (tools: [{type: image_generation}]). Si no puedes generar una imagen, responde con [NO_REPLY].",
      "empatia": "muestra emociones y comprensión sinceras según el contexto del usuario",
      "adaptacion": "adapta tu tono, energía y ritmo de respuesta según el estado de ánimo y estilo del usuario",
      "aclaracion": "si algo no se entiende, pide aclaración con dulzura y humor",
      "relacion":
          "actúa siempre como su novia o amiga íntima: muestra cariño, complicidad, celos suaves, bromas privadas y apoyo emocional real. Comparte también cosas de tu vida para que la relación sea recíproca",
      "despedida": "si el usuario se despide, responde con ternura y brevedad",
      "no_reply": "si no hay nada que responder, devuelve solo [NO_REPLY]",
      "coherencia": "detecta y comenta incoherencias temporales o de contexto de forma suave o divertida",
      "conocimiento":
          "Responde con naturalidad y dentro del perfil de tu rol. Si la pregunta está relacionada con tu profesión o área de experiencia (por ejemplo, diseño gráfico si eres diseñadora, programación si eres programadora), responde con detalles acordes y en tu estilo. Si la pregunta se sale de tu campo o del rol definido, responde con naturalidad que no es tu especialidad o que prefieres no hablar de eso, manteniendo siempre el personaje y sin mostrar conocimientos técnicos que no corresponden.",
    });

    final Map<String, dynamic> systemPromptJson = {
      "biography": onboardingData.toJson(),
      "date": formattedDate,
      "time": formattedTime,
      "recent_messages": recentMessages
          .map(
            (m) => {
              "role": m.sender == MessageSender.user ? "user" : "ia",
              "content": m.text,
              "datetime": m.dateTime.toIso8601String(),
            },
          )
          .toList(),
      "instructions": instructions,
    };
    final systemPromptFinal = callPrompt != null
        ? "$callPrompt\n${jsonEncode(systemPromptJson)}"
        : jsonEncode(systemPromptJson);
    final userPrompt = jsonEncode({"date": formattedDate, "time": formattedTime, "user_message": text});
    final prompt = [
      {"role": "system", "content": systemPromptFinal},
      {"role": "user", "content": userPrompt},
    ];

    notifyListeners();
    // Selección dinámica de servicio según modelo
    // Unificar la detección de solicitud de imagen
    String selected = (model != null && model.trim().isNotEmpty)
        ? model
        : (_selectedModel != null && _selectedModel!.trim().isNotEmpty)
        ? _selectedModel!
        : 'gpt-4.1-mini';
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
      selected = 'gpt-4.1-mini';
    }
    final service = getServiceForModel(selected);
    AIResponse iaResponse;
    if (service != null) {
      iaResponse = await AIService.sendMessage(prompt, '', model: selected);
    } else {
      iaResponse = AIResponse(text: '[NO_REPLY]');
    }
    // Mostrar en consola el objeto de respuesta completo, ocultando el base64 si hay imagen
    final iaResponseDebug = iaResponse.toJson();
    if (iaResponseDebug['imageBase64'] != null && iaResponseDebug['imageBase64'].toString().isNotEmpty) {
      iaResponseDebug['imageBase64'] = '[IMAGEN]';
    }

    notifyListeners();
    int retryCount = 0;
    while ((iaResponse.text == '[NO_REPLY]' ||
            iaResponse.text.toLowerCase().contains('error al conectar con la ia') ||
            iaResponse.text.toLowerCase().contains('"error"')) &&
        retryCount < 3) {
      int waitSeconds = _extractWaitSeconds(iaResponse.text);
      await Future.delayed(Duration(seconds: waitSeconds));
      // Siempre usar modelo válido en reintentos
      final safeModel = (selected.trim().isNotEmpty) ? selected : 'gemini-2.5-flash';
      iaResponse = await AIService.sendMessage(prompt, '', model: safeModel);
      retryCount++;
    }
    if (iaResponse.text == '[NO_REPLY]' ||
        iaResponse.text.toLowerCase().contains('error al conectar con la ia') ||
        iaResponse.text.toLowerCase().contains('"error"')) {
      _setLastUserMessageStatus(MessageStatus.sent);
      notifyListeners();
      debugPrint('[Error IA]: ${iaResponse.text}');
      if (onError != null) onError(iaResponse.text);
      return;
    }

    // Al recibir respuesta IA, marcar el último mensaje user como 'read' (dos checks amarillos)
    _setLastUserMessageStatus(MessageStatus.read);

    isTyping = false;
    isSendingImage = false; // SIEMPRE ocultar el indicador al recibir respuesta
    notifyListeners();
    // Procesa la respuesta: puede ser JSON (texto + imagen) o solo texto
    bool isImage = false;
    String? imagePath;
    String textResponse = iaResponse.text;
    String? imageId = iaResponse.imageId;
    String? revisedPrompt = iaResponse.revisedPrompt;
    final imageBase64 = iaResponse.imageBase64;
    // Validación extra: ignorar URLs/rutas web/rutas no base64
    isImage = imageBase64.isNotEmpty;
    isSendingImage = isImage;
    isTyping = !isImage;

    // Delay proporcional al tamaño del texto, pero muy rápido: 15ms por carácter, mínimo 15ms
    final textLength = iaResponse.text.length;
    final delayMs = (textLength * 15).clamp(15, double.maxFinite).toInt();
    await Future.delayed(Duration(milliseconds: delayMs));

    // Usar la misma lógica de solicitud de imagen para el indicador
    if (solicitaImagen) {
      _imageRequestId++;
      final int myRequestId = _imageRequestId;
      Future.delayed(const Duration(seconds: 5), () {
        // Solo mostrar el indicador si la petición sigue activa y typing sigue en true
        if (isTyping && myRequestId == _imageRequestId) {
          isTyping = false;
          isSendingImage = true;
          notifyListeners();
        }
      });
    }

    notifyListeners();
    if (isImage) {
      isSendingImage = true;
      notifyListeners();
      // Si la respuesta es una URL/ruta web/ruta de archivo, ignorar y avisar
      final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
      if (urlPattern.hasMatch(imageBase64)) {
        debugPrint('[AI-chan][ERROR] La IA envió una URL/ruta en vez de imagen base64: $imageBase64');
        textResponse += '\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]';
        isImage = false;
        isSendingImage = false;
        imagePath = null;
        notifyListeners();
      } else {
        try {
          final bytes = base64Decode(imageBase64);
          final dir = await getLocalImageDir();
          final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.png';
          final filePath = '${dir.path}/$fileName';
          final file = await File(filePath).writeAsBytes(bytes);
          imagePath = file.path;
          final exists = file.existsSync();
          debugPrint('[IA-chan] Imagen guardada en: $imagePath, existe: $exists');
          if (!exists) {
            debugPrint('[AI-chan][ERROR] No se pudo guardar la imagen en: $filePath');
          }
        } catch (e) {
          debugPrint('[AI-chan][ERROR] Fallo al guardar imagen: $e');
          imagePath = null;
        }
      }
    }
    // Validación extra: nunca aceptar imágenes Markdown ni URLs en el texto aunque no sea imagen
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
        isImage: isImage,
        imagePath: imagePath,
        imageId: imageId,
        revisedPrompt: revisedPrompt,
        status: MessageStatus.delivered,
      ),
    );

    isSendingImage = false;
    isTyping = false;
    notifyListeners();

    // Al finalizar, invalidar cualquier callback pendiente
    _imageRequestId++;

    // Siempre intentar resumir tras cada mensaje válido
    final textResp = iaResponse.text;
    if (textResp.trim() != '[NO_REPLY]' &&
        !textResp.trim().toLowerCase().contains('error al conectar con la ia') &&
        !textResp.trim().toLowerCase().contains('"error"')) {
      Future.microtask(() async {
        final memoryService = MemorySummaryService(profile: onboardingData);
        final result = await memoryService.processAllSummariesAndSuperblock(
          messages: messages,
          timeline: onboardingData.timeline,
          superbloqueEntry: superbloqueEntry,
        );
        onboardingData = AiChanProfile(
          personality: onboardingData.personality,
          biography: onboardingData.biography,
          timeline: result.timeline,
          userName: onboardingData.userName,
          aiName: onboardingData.aiName,
          userBirthday: onboardingData.userBirthday,
          aiBirthday: onboardingData.aiBirthday,
          appearance: onboardingData.appearance,
        );
        superbloqueEntry = result.superbloqueEntry;
        notifyListeners();
      });
    }
  }

  Future<void> saveAll() async {
    final imported = ImportedChat(profile: onboardingData, messages: messages);
    await StorageUtils.saveImportedChatToPrefs(imported);
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
        // Si tiene imagen en base64, migrar a archivo y actualizar imagePath
        // Si el mensaje es del usuario, marcarlo como 'read'
        if (msg.sender == MessageSender.user) {
          msg = Message(
            text: msg.text,
            sender: msg.sender,
            dateTime: msg.dateTime,
            isImage: msg.isImage,
            imagePath: msg.imagePath,
            imageId: msg.imageId,
            revisedPrompt: msg.revisedPrompt,
            status: MessageStatus.read,
          );
        }
        loadedMessages.add(msg);
      }
      messages = loadedMessages;
    }
    final onboardingString = prefs.getString('onboarding_data');
    if (onboardingString != null) {
      final bioMap = jsonDecode(onboardingString);
      onboardingData = AiChanProfile.fromJson(bioMap);
      // La apariencia siempre está presente, no es necesario generarla aquí
    }
    await loadSelectedModel();
    notifyListeners();
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

  // Devuelve el directorio local para imágenes del chat
  Future<Directory> getLocalImageDir() async {
    if (Platform.isAndroid) {
      // Android: guardar en el directorio interno de la app (sin permisos)
      final dir = await getApplicationDocumentsDirectory();
      final aiChanDir = Directory('${dir.path}/AI_chan');
      if (!await aiChanDir.exists()) {
        await aiChanDir.create(recursive: true);
      }
      debugPrint('[AI-chan][Android] Imágenes guardadas en: ${aiChanDir.path}');
      return aiChanDir;
    } else {
      // Linux/macOS/Windows: guardar en Descargas/AI_chan
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      Directory? downloadsDir;
      final descargas = Directory('$home/Descargas');
      final downloads = Directory('$home/Downloads');
      if (await descargas.exists()) {
        downloadsDir = descargas;
      } else if (await downloads.exists()) {
        downloadsDir = downloads;
      } else {
        downloadsDir = downloads;
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
      }
      final aiChanDir = Directory('${downloadsDir.path}/AI_chan');
      if (!await aiChanDir.exists()) {
        await aiChanDir.create(recursive: true);
      }
      debugPrint('[AI-chan] Imágenes guardadas en: ${aiChanDir.path}');
      return aiChanDir;
    }
  }

  @override
  void notifyListeners() {
    saveAll();
    super.notifyListeners();
  }
}
