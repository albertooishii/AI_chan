import 'package:ai_chan/utils/storage_utils.dart';
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
import '../services/memory_summary_service.dart';
import 'dart:io';
import '../services/ia_appearance_generator.dart';
import '../services/ai_service.dart';
import '../services/event_service.dart';
import '../services/promise_service.dart';
import '../services/image_request_service.dart';
import '../services/openai_service.dart';
import '../services/audio_chat_service.dart';
import '../services/periodic_ia_message_scheduler.dart';
import '../services/prompt_builder.dart';
import '../services/ai_chat_response_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider() {
    // Inicializar servicio de audio delegando notificaciones al provider
    audioService = AudioChatService(onStateChanged: () => notifyListeners(), onWaveform: (_) => notifyListeners());
  }
  final PeriodicIaMessageScheduler _periodicScheduler = PeriodicIaMessageScheduler();

  void startPeriodicIaMessages() {
    _periodicScheduler.start(
      profileGetter: () => onboardingData,
      messagesGetter: () => messages,
      triggerSend: (prompt, model) => sendMessage('', callPrompt: prompt, model: model),
    );
  }

  // Lógica de horarios / periodicidad movida a PeriodicIaMessageScheduler & ScheduleUtils

  /// Detener el envío automático de mensajes IA
  void stopPeriodicIaMessages() => _periodicScheduler.stop();

  final PromptBuilder _promptBuilder = PromptBuilder();

  String buildRealtimeSystemPromptJson({int maxRecent = 32}) =>
      _promptBuilder.buildRealtimeSystemPromptJson(profile: onboardingData, messages: messages, maxRecent: maxRecent);

  /// Construye un SystemPrompt (JSON) específico para llamadas de voz.
  /// Reutiliza el mismo perfil, timeline y últimos [maxRecent] mensajes,
  /// pero con instrucciones adaptadas a la modalidad de llamada:
  /// - No pedir/ofrecer fotos ni imágenes durante la llamada.
  /// - No usar enlaces/URLs, clics, Markdown, ni hablar de herramientas.
  /// - Estilo oral: frases cortas (2–8 s), pausas naturales, sin monólogos.
  /// - No presentarse como "asistente" o "IA"; mantener la misma persona del chat.
  String buildCallSystemPromptJson({int maxRecent = 32}) =>
      _promptBuilder.buildCallSystemPromptJson(profile: onboardingData, messages: messages, maxRecent: maxRecent);

  // Sanitización y construcción de prompts movidos a PromptBuilder
  // ...existing code...

  // Getter público para los eventos programados IA
  List<EventEntry> get events => _events;
  // ...existing code...

  // Eventos (incluye promesas) y servicio de programación de promesas
  final List<EventEntry> _events = [];
  static const String _eventsKey = 'events';

  late final PromiseService _promiseService = PromiseService(
    events: _events,
    onEventsChanged: () => notifyListeners(),
    sendSystemPrompt: (text, {String? callPrompt, String? model}) =>
        sendMessage(text, callPrompt: callPrompt, model: model),
  );
  void schedulePromiseEvent(EventEntry e) => _promiseService.schedulePromiseEvent(e);
  void onIaMessageSent() => _promiseService.analyzeAfterIaMessage(messages);

  void _setLastUserMessageStatus(MessageStatus status) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.sender == MessageSender.user) {
        if (m.status != status) {
          messages[i] = m.copyWith(status: status);
          notifyListeners();
        }
        return;
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
    // Nuevo: adjuntar transcripción ya preparada de un audio (para no volver a transcribir)
    String? preTranscribedText,
    // Nuevo: si el usuario ha mandado nota de voz, guardamos ruta del audio
    String? userAudioPath,
  }) async {
    final now = DateTime.now();
    // Reset racha si hay actividad real del usuario (texto no vacío o imagen) y no es prompt automático
    // Racha de autos ahora gestionada dentro de PeriodicIaMessageScheduler; no se requiere flag local aquí
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
    // Guardar siempre el texto (incluida transcripción) para contexto IA; la UI decide mostrarlo (audio oculto).
    String displayText;
    if (isAutomaticPrompt) {
      // isAutomaticPrompt implica callPrompt != null y no vacío
      displayText = callPrompt; // safe: isAutomaticPrompt asegura no null
    } else {
      displayText = preTranscribedText ?? text;
    }
    final msg = Message(
      text: displayText,
      sender: isAutomaticPrompt ? MessageSender.system : MessageSender.user,
      dateTime: now,
      isImage: hasImage,
      image: hasImage ? imageForHistory : null,
      isAudio: userAudioPath != null,
      audioPath: userAudioPath,
      status: MessageStatus.sending,
    );
    if (text.trim().isNotEmpty || hasImage || isAutomaticPrompt || userAudioPath != null) {
      messages.add(msg);
      if (userAudioPath != null) {
        try {
          final f = File(userAudioPath);
          debugPrint(
            '[Audio] sendMessage added msg with audioPath=$userAudioPath exists=${f.existsSync()} size=${f.existsSync() ? f.lengthSync() : 0}',
          );
        } catch (_) {}
      }
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
    // Sincronizar _events con los eventos del perfil tras cada actualización
    _events
      ..clear()
      ..addAll(onboardingData.events ?? []);

    // Usar PromptBuilder para construir el SystemPrompt completo (evita duplicación con buildRealtimeSystemPromptJson)
    final systemPromptJson = _promptBuilder.buildRealtimeSystemPromptJson(
      profile: onboardingData,
      messages: messages,
      maxRecent: maxHistory ?? 32,
    );
    final systemPromptObj = SystemPrompt.fromJson(jsonDecode(systemPromptJson));

    // Seleccionar modelo base
    String selected = (model != null && model.trim().isNotEmpty)
        ? model
        : (_selectedModel != null && _selectedModel!.trim().isNotEmpty)
        ? _selectedModel!
        : 'gemini-2.5-flash';

    // Detección de petición de imagen (solo si no es prompt automático)
    bool solicitaImagen = false;
    if (!isAutomaticPrompt) {
      final List<String> recentUserHistory = [];
      int startIdx = messages.length - 1;
      if (messages.isNotEmpty && messages.last.sender == MessageSender.user) {
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
    // Si el usuario adjuntó una imagen, NO considerarlo como petición para que la IA genere
    // una nueva imagen: estamos enviando la imagen del usuario para analizarla.
    if (hasImage) {
      solicitaImagen = false;
      debugPrint('[AI-chan] Imagen adjunta por el usuario: omitiendo detección de solicitud de imagen.');
    }
    if (solicitaImagen) {
      final lower = selected.toLowerCase();
      if (!lower.startsWith('gpt-')) {
        debugPrint('[AI-chan] Solicitud de imagen detectada. Forzando modelo "gpt-4.1-mini"');
        selected = 'gpt-4.1-mini';
      }
    }

    // Enviar vía servicio modularizado (maneja reintentos y base64)
    final result = await AiChatResponseService.send(
      recentMessages: recentMessages,
      systemPromptObj: systemPromptObj,
      model: selected,
      imageBase64: image?.base64,
      imageMimeType: imageMimeType,
      enableImageGeneration: solicitaImagen,
    );

    if (result.text.toLowerCase().contains('error al conectar con la ia') && !result.isImage) {
      _setLastUserMessageStatus(MessageStatus.sent);
      notifyListeners();
      if (onError != null) onError(result.text);
      return;
    }

    // Persistir prompt extraído en imagen del usuario (si aplica)
    if (hasImage && (result.prompt?.trim().isNotEmpty ?? false)) {
      // El mensaje de imagen es el que acabamos de añadir: tomar el último mensaje de usuario con imagen.
      final idx = messages.lastIndexWhere((m) => m.sender == MessageSender.user && m.isImage);
      if (idx != -1) {
        final prevImage = messages[idx].image;
        if (prevImage != null) {
          messages[idx] = messages[idx].copyWith(image: prevImage.copyWith(prompt: result.prompt));
          notifyListeners();
        }
      } else {
        debugPrint(
          '[AI-chan] No se encontró mensaje de imagen reciente para asignar prompt; prompt extraído: ${result.prompt}',
        );
      }
    }

    _setLastUserMessageStatus(MessageStatus.read);

    // Indicadores de escritura / imagen
    isTyping = !result.isImage;
    isSendingImage = result.isImage;
    debugPrint('[AI] isTyping=$isTyping, isSendingImage=$isSendingImage (sendMessage)');
    final textLength = result.text.length;
    final delayMs = (textLength * 15).clamp(15, double.maxFinite).toInt();
    await Future.delayed(Duration(milliseconds: delayMs));

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

    // Normalizar posibles espacios o saltos de línea antes de la etiqueta de nota de voz
    // Usamos etiquetas emparejadas: [audio]contenido[/audio]
    String assistantRawText = result.text;
    // Construir tags con corchetes a partir de la clave
    final openTag = '[audio]';
    final closeTag = '[/audio]';
    final leftTrimmed = assistantRawText.trimLeft();
    final leftLower = leftTrimmed.toLowerCase();
    // Solo aceptar como nota de voz si hay apertura y cierre exactos
    if (leftLower.startsWith(openTag)) {
      final afterTag = leftTrimmed.substring(openTag.length).trimLeft();
      final lowerAfter = afterTag.toLowerCase();
      if (lowerAfter.contains(closeTag)) {
        final endIdx = lowerAfter.indexOf(closeTag);
        final content = afterTag.substring(0, endIdx).trim();
        assistantRawText = '$openTag $content $closeTag';
      } else {
        // No hay cierre: no lo tratamos como nota de voz — dejar el texto sin cambios
      }
    }
    final assistantMessage = Message(
      text: assistantRawText,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: result.isImage,
      image: result.isImage
          ? ai_image.Image(url: result.imagePath ?? '', seed: result.seed, prompt: result.prompt)
          : null,
      status: MessageStatus.delivered,
    );
    messages.add(assistantMessage);
    // Generar TTS solo si la IA explícitamente marca su respuesta como nota de voz
    try {
      if (!assistantMessage.isAudio && assistantMessage.text.toLowerCase().contains('[audio]')) {
        await generateTtsForMessage(assistantMessage);
      }
    } catch (_) {}

    // --- DETECCIÓN Y GUARDADO AUTOMÁTICO DE EVENTOS/CITAS Y HORARIOS ---
    // Modularizado: solo llamadas a servicios externos
    final updatedProfile = await EventTimelineService.detectAndSaveEventAndSchedule(
      text: text,
      textResponse: result.text,
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
    // No resetear isSendingAudio aquí si estamos procesando/ enviando una nota de voz
    // El control de isSendingAudio lo gestiona quien inició el envío (stopAndSendRecording)
    if (userAudioPath == null) {
      isSendingAudio = false;
      debugPrint('[AI] isSendingAudio = false (sendMessage)');
    } else {
      debugPrint('[AI] preserve isSendingAudio (sendMessage) because userAudioPath != null');
    }
    _imageRequestId++;

    final textResp = result.text;
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

  // ================= NUEVO BLOQUE AUDIO =================
  late final AudioChatService audioService;

  bool get isRecording => audioService.isRecording;
  List<int> get currentWaveform => audioService.currentWaveform;
  String get liveTranscript => audioService.liveTranscript;
  Duration get recordingElapsed => audioService.recordingElapsed;

  Future<void> startRecording() => audioService.startRecording();

  Future<void> stopAndSendRecording({String? model}) async {
    final path = await audioService.stopRecording();
    debugPrint('[Audio] stopAndSendRecording got path: $path');
    if (path == null) return; // cancelado o error

    // Activar indicador de envío de audio
    debugPrint('[Audio] isSendingAudio = true (stopAndSendRecording)');
    isSendingAudio = true;
    notifyListeners();

    String? transcript;

    // Intentar transcripción con OpenAI con reintentos
    int retries = 0;
    const maxRetries = 2;
    while (retries <= maxRetries && transcript == null) {
      try {
        final openai = OpenAIService();
        transcript = await openai.transcribeAudio(path);
        if (transcript != null && transcript.trim().isNotEmpty) {
          debugPrint('[Audio] Transcripción exitosa en intento ${retries + 1}');
          break;
        }
      } catch (e) {
        retries++;
        debugPrint('[Audio] Error transcribiendo (intento $retries/$maxRetries): $e');
        if (retries <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retries)); // backoff progresivo
        }
      }
    }

    // Fallback: usar transcripción en vivo si la final falló o es muy corta
    if ((transcript == null || transcript.trim().length < liveTranscript.trim().length) && liveTranscript.isNotEmpty) {
      transcript = liveTranscript.trim();
      debugPrint('[Audio] Usando transcripción en vivo como fallback');
    }

    // Si la transcripción está vacía, descartar y eliminar archivo.
    if (transcript == null || transcript.trim().isEmpty) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      debugPrint('[Audio] Nota de voz vacía descartada (no se añade mensaje)');
      isSendingAudio = false;
      notifyListeners();
      return;
    }

    // Envolver la transcripción en etiquetas emparejadas [audio]texto[/audio]
    final tagged = '[audio]${transcript.trim()}[/audio]';

    await sendMessage(tagged, model: model, userAudioPath: path, preTranscribedText: tagged);

    // Desactivar indicador de envío de audio
    debugPrint('[Audio] isSendingAudio = false (stopAndSendRecording)');
    isSendingAudio = false;
    notifyListeners();
  }

  Future<void> cancelRecording() => audioService.cancelRecording();

  Future<void> togglePlayAudio(Message msg) => audioService.togglePlay(msg, () => notifyListeners());

  bool isPlaying(Message msg) => audioService.isPlayingMessage(msg);

  Future<void> generateTtsForMessage(Message msg, {String voice = 'nova'}) async {
    if (msg.sender != MessageSender.assistant || msg.isAudio) return;
    final file = await audioService.synthesizeTts(msg.text, voice: voice);
    if (file != null) {
      final idx = messages.indexOf(msg);
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(isAudio: true, audioPath: file.path, autoTts: true);
        notifyListeners();
      }
    }
  }
  // =======================================================

  /// Añade un mensaje de imagen enviado por el usuario
  void addUserImageMessage(Message msg) {
    messages.add(msg);
    saveAll();
    notifyListeners();
  }

  /// Añade un mensaje del asistente directamente (p.ej., resumen de llamada de voz)
  Future<void> addAssistantMessage(String text, {bool isAudio = false}) async {
    final msg = Message(
      text: text,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: false,
      image: null,
      // audioPath eliminado
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

  // _extractWaitSeconds eliminado (reintentos ahora están en AiChatResponseService)

  /// Limpia el texto para mostrarlo correctamente en el chat (quita escapes JSON)
  String cleanText(String text) {
    return text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }

  bool isSummarizing = false;
  bool isTyping = false;
  bool isSendingImage = false;
  bool isSendingAudio = false;
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
    _promiseService.restoreFromEvents();
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
    await loadSelectedModel();
    // Reprogramar promesas IA futuras desde events
    _promiseService.restoreFromEvents();
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

  @override
  void dispose() {
    audioService.dispose();
    super.dispose();
  }
}

// (Legacy IaPromiseService eliminado; PromiseService unifica la lógica de promesas)
