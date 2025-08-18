import 'package:ai_chan/utils/storage_utils.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import '../utils/chat_json_utils.dart' as chat_json_utils;
import '../services/memory_summary_service.dart';
import 'dart:io';
import '../services/ia_appearance_generator.dart';
import '../services/ai_service.dart';
import '../services/event_service.dart';
import '../services/promise_service.dart';
import '../services/image_request_service.dart';
import '../services/audio_chat_service.dart';
import '../services/google_speech_service.dart';
import '../services/periodic_ia_message_scheduler.dart';
import '../services/prompt_builder.dart';
import '../services/ai_chat_response_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import '../utils/log_utils.dart';

class ChatProvider extends ChangeNotifier {
  final IChatRepository? repository;
  final IAIService? aiService;
  final IChatResponseService? chatResponseService;

  ChatProvider({this.repository, this.aiService, this.chatResponseService}) {
    // AudioService se inicializa perezosamente en la primera llamada (evita inicializar plugins en tests)
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
  String buildCallSystemPromptJson({int maxRecent = 32, required bool aiInitiatedCall}) =>
      _promptBuilder.buildCallSystemPromptJson(
        profile: onboardingData,
        messages: messages,
        maxRecent: maxRecent,
        aiInitiatedCall: aiInitiatedCall,
      );

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
    AiImage? image,
    String? imageMimeType,
    // Nuevo: adjuntar transcripción ya preparada de un audio (para no volver a transcribir)
    String? preTranscribedText,
    // Nuevo: si el usuario ha mandado nota de voz, guardamos ruta del audio
    String? userAudioPath,
    // existingMessageIndex: si se proporciona, reusar el mensaje en esa posición (para reintentos)
    int? existingMessageIndex,
  }) async {
    final now = DateTime.now();
    // Reset racha si hay actividad real del usuario (texto no vacío o imagen) y no es prompt automático
    // Racha de autos ahora gestionada dentro de PeriodicIaMessageScheduler; no se requiere flag local aquí
    // Detectar si es mensaje con imagen
    final bool hasImage = image != null && (((image.base64 ?? '').isNotEmpty) || ((image.url ?? '').isNotEmpty));
    // Solo añadir el mensaje si no es vacío (o si tiene imagen)
    // Si es mensaje automático (callPrompt, texto vacío), NO añadir a la lista de mensajes enviados
    final isAutomaticPrompt = text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);
    // Si el mensaje tiene imagen, NO guardar el base64 en el historial, solo la URL local
    AiImage? imageForHistory;
    if (hasImage) {
      imageForHistory = AiImage(url: image.url, seed: image.seed, prompt: image.prompt);
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
      image: imageForHistory,
      isAudio: userAudioPath != null,
      audioPath: userAudioPath,
      status: MessageStatus.sending,
    );
    if (text.trim().isNotEmpty || hasImage || isAutomaticPrompt || userAudioPath != null) {
      if (existingMessageIndex != null && existingMessageIndex >= 0 && existingMessageIndex < messages.length) {
        // Reintento: sobrescribir estado del mensaje existente en lugar de añadir uno nuevo
        messages[existingMessageIndex] = messages[existingMessageIndex].copyWith(
          status: MessageStatus.sending,
          text: msg.text,
          image: msg.image,
          isAudio: msg.isAudio,
          audioPath: msg.audioPath,
        );
      } else {
        messages.add(msg);
      }
      if (userAudioPath != null) {
        try {
          final f = File(userAudioPath);
          Log.d(
            '[Audio] sendMessage added msg con audioPath=$userAudioPath exists=${f.existsSync()} size=${f.existsSync() ? f.lengthSync() : 0}',
            tag: 'AUDIO',
          );
        } catch (_) {}
      }
      notifyListeners();
    }

    // Mantener en sending hasta que la petición sea aceptada por el servicio.
    // Marcamos como 'sent' justo después de obtener respuesta del servicio IA (éxito de red) y antes de marcar 'read'.

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
    String selected;
    if (model != null && model.trim().isNotEmpty) {
      selected = model;
    } else if (_selectedModel != null && _selectedModel!.trim().isNotEmpty) {
      final s = _selectedModel!.trim();
      selected = s;
    } else {
      selected = 'gemini-2.5-flash';
    }

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
      Log.i('Imagen adjunta por el usuario: omitiendo detección de solicitud de imagen.', tag: 'CHAT');
    }
    if (solicitaImagen) {
      final lower = selected.toLowerCase();
      if (!lower.startsWith('gpt-')) {
        Log.i('Solicitud de imagen detectada. Forzando modelo "gpt-4.1-mini"', tag: 'CHAT');
        selected = 'gpt-4.1-mini';
      }
    }

    // Enviar vía servicio modularizado (maneja reintentos y base64)
    AIChatResult result;
    try {
      if (chatResponseService != null) {
        // Convert recentMessages -> List<Map> expected por la interfaz
        final msgs = recentMessages
            .map(
              (m) => {
                'role': m.sender == MessageSender.user
                    ? 'user'
                    : (m.sender == MessageSender.assistant ? 'ia' : 'system'),
                'content': m.text,
                'datetime': m.dateTime.toIso8601String(),
              },
            )
            .toList();
        final mapResult = await chatResponseService!.sendChat(
          msgs,
          options: {
            'systemPromptObj': systemPromptObj.toJson(),
            'model': selected,
            'imageBase64': image?.base64,
            'imageMimeType': imageMimeType,
            'enableImageGeneration': solicitaImagen,
          },
        );
        // Map -> AIChatResult
        result = AIChatResult(
          text: mapResult['text'] as String? ?? '',
          isImage: mapResult['isImage'] as bool? ?? false,
          imagePath: mapResult['imagePath'] as String?,
          prompt: mapResult['prompt'] as String?,
          seed: mapResult['seed'] as String?,
          finalModelUsed: mapResult['finalModelUsed'] as String? ?? selected,
        );
      } else {
        // Resolver una implementación por medio de la fábrica DI y usar la interfaz
        final impl = di.getChatResponseService();
        final msgs = recentMessages
            .map(
              (m) => {
                'role': m.sender == MessageSender.user
                    ? 'user'
                    : (m.sender == MessageSender.assistant ? 'ia' : 'system'),
                'content': m.text,
                'datetime': m.dateTime.toIso8601String(),
              },
            )
            .toList();
        final mapResult = await impl.sendChat(
          msgs,
          options: {
            'systemPromptObj': systemPromptObj.toJson(),
            'model': selected,
            'imageBase64': image?.base64,
            'imageMimeType': imageMimeType,
            'enableImageGeneration': solicitaImagen,
          },
        );
        result = AIChatResult(
          text: mapResult['text'] as String? ?? '',
          isImage: mapResult['isImage'] as bool? ?? false,
          imagePath: mapResult['imagePath'] as String?,
          prompt: mapResult['prompt'] as String?,
          seed: mapResult['seed'] as String?,
          finalModelUsed: mapResult['finalModelUsed'] as String? ?? selected,
        );
      }
      // Éxito de red: marcar último mensaje usuario como 'sent'
      _setLastUserMessageStatus(MessageStatus.sent);
    } catch (e) {
      Log.e('Error enviando mensaje', tag: 'CHAT', error: e);
      // Marcar último mensaje de usuario como failed
      // Preferir existingMessageIndex si se proporcionó
      int idx = -1;
      if (existingMessageIndex != null && existingMessageIndex >= 0 && existingMessageIndex < messages.length) {
        idx = existingMessageIndex;
      } else {
        idx = messages.lastIndexWhere((m) => m.sender == MessageSender.user);
      }
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(status: MessageStatus.failed);
        notifyListeners();
      }
      if (onError != null) onError(e.toString());
      return;
    }

    // Manejo de errores reportados por el servicio (texto de error)
    if (result.text.toLowerCase().contains('error al conectar con la ia') && !result.isImage) {
      // Marcar mensaje como failed para permitir reintento manual
      int idx = (existingMessageIndex != null && existingMessageIndex >= 0 && existingMessageIndex < messages.length)
          ? existingMessageIndex
          : messages.lastIndexWhere((m) => m.sender == MessageSender.user);
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(status: MessageStatus.failed);
        notifyListeners();
      }
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
        Log.i(
          'No se encontró mensaje de imagen reciente para asignar prompt; prompt extraído: ${result.prompt}',
          tag: 'CHAT',
        );
      }
    }

    // Ahora ya tenemos la respuesta completa: marcar como 'read'
    _setLastUserMessageStatus(MessageStatus.read);

    // Indicadores de escritura / imagen
    isTyping = !result.isImage;
    isSendingImage = result.isImage;
    // Si la IA marca su respuesta como nota de voz ([audio]...[/audio]) activamos el indicador
    final lowerResultText = result.text.toLowerCase();
    if (lowerResultText.contains('[audio]')) {
      isSendingAudio = true; // Se desactiva al final del flujo cuando termina la síntesis TTS
    }
    Log.d(
      'isTyping=$isTyping, isSendingImage=$isSendingImage, isSendingAudio=$isSendingAudio (sendMessage)',
      tag: 'CHAT',
    );
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
      image: result.isImage ? AiImage(url: result.imagePath ?? '', seed: result.seed, prompt: result.prompt) : null,
      status: MessageStatus.read,
    );
    messages.add(assistantMessage);
    // Detección de llamada entrante cuando el modelo responde con el placeholder exacto
    if (assistantMessage.text.trim() == '[call][/call]') {
      pendingIncomingCallMsgIndex = messages.length - 1;
      Log.i('[Call] Placeholder de llamada entrante detectado (index=$pendingIncomingCallMsgIndex)', tag: 'CHAT');
      // Notificar ya para que la UI abra la pantalla de llamada sin esperar al resto del post-procesado
      notifyListeners();
    }
    // Generar TTS solo si la IA explícitamente marca su respuesta como nota de voz
    try {
      if (!assistantMessage.isAudio) {
        final lower = assistantMessage.text.toLowerCase();
        final openTag = '[audio]';
        final closeTag = '[/audio]';
        final hasOpen = lower.contains(openTag);
        final hasClose = lower.contains(closeTag);
        if (hasOpen && hasClose) {
          final start = lower.indexOf(openTag) + openTag.length;
          final end = lower.indexOf(closeTag, start);
          if (end > start) {
            final inner = assistantMessage.text.substring(start, end).trim();
            // Solo generar si hay texto real entre las etiquetas
            if (inner.isNotEmpty) {
              await generateTtsForMessage(assistantMessage);
            }
          }
        }
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
    isSendingAudio = false;
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
    // Si se agregó un placeholder de llamada entrante ya se notificó antes (evitamos doble render inmediato)
    if (assistantMessage.text.trim() != '[call][/call]') {
      notifyListeners();
    }
  }

  // ================= NUEVO BLOQUE AUDIO =================
  AudioChatService? _audioService;

  AudioChatService get audioService =>
      _audioService ??= AudioChatService(onStateChanged: () => notifyListeners(), onWaveform: (_) => notifyListeners());

  bool get isRecording => audioService.isRecording;
  List<int> get currentWaveform => audioService.currentWaveform;
  String get liveTranscript => audioService.liveTranscript;
  Duration get recordingElapsed => audioService.recordingElapsed;

  Future<void> startRecording() => audioService.startRecording();

  Future<void> stopAndSendRecording({String? model}) async {
    final path = await audioService.stopRecording();
    Log.d('stopAndSendRecording got path: $path', tag: 'AUDIO');
    if (path == null) return; // cancelado o error

    // Activar indicador de envío de audio
    Log.d('isUploadingUserAudio = true (stopAndSendRecording)', tag: 'AUDIO');
    isUploadingUserAudio = true;
    notifyListeners();

    String? transcript;

    // Intentar transcripción con OpenAI con reintentos
    int retries = 0;
    const maxRetries = 2;
    while (retries <= maxRetries && transcript == null) {
      try {
        final stt = di.getSttService();
        transcript = await stt.transcribeAudio(path);
        if (transcript != null && transcript.trim().isNotEmpty) {
          Log.i('Transcripción exitosa en intento ${retries + 1}', tag: 'AUDIO');
          break;
        }
      } catch (e) {
        retries++;
        Log.e('Error transcribiendo (intento $retries/$maxRetries)', tag: 'AUDIO', error: e);
        if (retries <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retries)); // backoff progresivo
        }
      }
    }

    // Fallback: usar transcripción en vivo si la final falló o es muy corta
    if ((transcript == null || transcript.trim().length < liveTranscript.trim().length) && liveTranscript.isNotEmpty) {
      transcript = liveTranscript.trim();
      Log.w('Usando transcripción en vivo como fallback', tag: 'AUDIO');
    }

    // Si la transcripción está vacía, descartar y eliminar archivo.
    if (transcript == null || transcript.trim().isEmpty) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      Log.w('Nota de voz vacía descartada (no se añade mensaje)', tag: 'AUDIO');
      isUploadingUserAudio = false;
      notifyListeners();
      return;
    }

    // Envolver la transcripción en etiquetas emparejadas [audio]texto[/audio]
    final tagged = '[audio]${transcript.trim()}[/audio]';

    await sendMessage(tagged, model: model, userAudioPath: path, preTranscribedText: tagged);

    // Desactivar indicador de envío de audio
    Log.d('isUploadingUserAudio = false (stopAndSendRecording)', tag: 'AUDIO');
    isUploadingUserAudio = false;
    notifyListeners();
  }

  Future<void> cancelRecording() => audioService.cancelRecording();

  Future<void> togglePlayAudio(Message msg) => audioService.togglePlay(msg, () => notifyListeners());

  bool isPlaying(Message msg) => audioService.isPlayingMessage(msg);
  Duration get playingPosition => audioService.currentPosition;
  Duration get playingDuration => audioService.currentDuration;

  Future<void> generateTtsForMessage(Message msg, {String voice = 'nova'}) async {
    if (msg.sender != MessageSender.assistant || msg.isAudio) return;
    String? lang;
    // Heurística: si la voz parece una voz de Google (contiene guion y dos letras al inicio), intentar resolver languageCode
    if (voice.contains('-') && RegExp(r'^[a-zA-Z]{2}-').hasMatch(voice)) {
      try {
        final all = await GoogleSpeechService.fetchGoogleVoices();
        final found = all.firstWhere((v) => (v['name'] as String?) == voice, orElse: () => {});
        if (found.isNotEmpty) {
          final lcodes = (found['languageCodes'] as List<dynamic>?)?.cast<String>() ?? [];
          if (lcodes.isNotEmpty) lang = lcodes.first;
        }
      } catch (_) {}
    }
    final file = await audioService.synthesizeTts(msg.text, voice: voice, languageCode: lang);
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
    final isCallPlaceholder = text.trim() == '[call][/call]';
    final msg = Message(
      text: text,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: false,
      image: null,
      status: MessageStatus.read,
      callStatus: isCallPlaceholder ? CallStatus.placeholder : null,
    );
    messages.add(msg);
    // Detección de llamada entrante solicitada por la IA mediante [call][/call]
    if (text.trim() == '[call][/call]') {
      pendingIncomingCallMsgIndex = messages.length - 1;
    }
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
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-voz: $e');
    }
  }

  /// Crea o actualiza un mensaje de estado de llamada (rechazada, no contestada, cancelada, placeholder).
  /// Nunca usa sender system; se asigna assistant para llamadas entrantes (placeholder original assistant) y user para salientes.
  Future<void> updateOrAddCallStatusMessage({
    required String text,
    required CallStatus callStatus,
    bool incoming = false,
    int? placeholderIndex,
  }) async {
    // Determinar sender deseado
    final MessageSender sender = incoming ? MessageSender.assistant : MessageSender.user;

    // Si hay placeholder entrante y se pasa índice, reemplazarlo conservando fecha original si existe
    if (placeholderIndex != null && placeholderIndex >= 0 && placeholderIndex < messages.length) {
      final original = messages[placeholderIndex];
      messages[placeholderIndex] = Message(
        text: text,
        sender: sender,
        dateTime: original.dateTime,
        status: MessageStatus.read,
        callStatus: callStatus,
      );
      if (pendingIncomingCallMsgIndex == placeholderIndex) pendingIncomingCallMsgIndex = null;
    } else {
      // Añadir nuevo mensaje de estado
      messages.add(
        Message(
          text: text,
          sender: sender,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
          callStatus: callStatus,
        ),
      );
    }
    notifyListeners();
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
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-updateCallStatus: $e');
    }
  }

  /// Añade un mensaje directamente (p.ej., resumen de llamada de voz)
  Future<void> addUserMessage(Message message) async {
    // Completar callStatus si viene con duración y no está seteado
    if (message.callDuration != null && message.callStatus == null) {
      message = message.copyWith(callStatus: CallStatus.completed);
    }
    messages.add(message);
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
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-message: $e');
    }
  }

  // ======== Soporte llamada entrante ========
  int? pendingIncomingCallMsgIndex; // índice del mensaje [call][/call] pendiente de contestar

  bool get hasPendingIncomingCall => pendingIncomingCallMsgIndex != null;

  void clearPendingIncomingCall() {
    pendingIncomingCallMsgIndex = null;
    notifyListeners();
  }

  /// Reemplaza el mensaje placeholder [call][/call] por el resumen final de la llamada.
  void replaceIncomingCallPlaceholder({
    required int index,
    required VoiceCallSummary summary,
    required String summaryText,
  }) {
    if (index < 0 || index >= messages.length) return;
    final original = messages[index];
    if (!original.text.contains('[call]')) return; // sanity
    // Mantener el sender original (assistant) para diferenciar "recibida" en la UI.
    messages[index] = Message(
      text: summaryText,
      sender: original.sender,
      dateTime: summary.startTime,
      callDuration: summary.duration,
      callEndTime: summary.endTime,
      status: MessageStatus.read,
      callStatus: CallStatus.completed,
    );
    pendingIncomingCallMsgIndex = null;
    notifyListeners();
    // Actualizar memoria igual que otros mensajes
    () async {
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
        Log.w('[AI-chan][WARN] Falló actualización de memoria post-replace-call: $e');
      }
    }();
  }

  /// Marca una llamada entrante como rechazada antes de que hubiera conversación.
  void rejectIncomingCallPlaceholder({required int index, String text = 'Llamada rechazada'}) {
    if (index < 0 || index >= messages.length) return;
    final original = messages[index];
    if (!original.text.contains('[call]')) return;
    messages[index] = Message(
      text: text,
      // Mantener el sender original (assistant) para reflejar que provino de llamada IA
      sender: original.sender,
      dateTime: DateTime.now(),
      status: MessageStatus.read,
      callStatus: text.toLowerCase().contains('no contestada') ? CallStatus.missed : CallStatus.rejected,
    );
    pendingIncomingCallMsgIndex = null;
    notifyListeners();
    () async {
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
        Log.w('[AI-chan][WARN] Falló actualización de memoria post-reject-call: $e');
      }
    }();
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
  bool isUploadingUserAudio = false;
  List<Message> messages = [];
  late AiChanProfile onboardingData;

  Future<String> exportAllToJson() async {
    final export = ChatExport(profile: onboardingData, messages: messages, events: _events);
    final map = export.toJson();
    if (repository != null) {
      try {
        return await repository!.exportAllToJson(map);
      } catch (_) {
        // fallback to local encoding
      }
    }
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(map);
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
    // Prefer repository if provided
    if (repository != null) {
      try {
        await repository!.saveAll(exported.toJson());
        return;
      } catch (e) {
        Log.w('IChatRepository.saveAll failed, falling back to StorageUtils: $e', tag: 'PERSIST');
      }
    }
    // Fallback: legacy StorageUtils
    try {
      await StorageUtils.saveImportedChatToPrefs(exported);
    } catch (e) {
      Log.w('StorageUtils.saveImportedChatToPrefs failed: $e', tag: 'PERSIST');
    }
  }

  Future<void> loadAll() async {
    // Try to load via repository if available
    if (repository != null) {
      try {
        final Map<String, dynamic>? data = await repository!.loadAll();
        if (data != null) {
          try {
            final imported = ImportedChat.fromJson(data);
            onboardingData = imported.profile;
            messages = imported.messages.cast<Message>();
            _events.clear();
            if (imported.events.isNotEmpty) _events.addAll(imported.events);
            await loadSelectedModel();
            _promiseService.restoreFromEvents();
            notifyListeners();
            startPeriodicIaMessages();
            return;
          } catch (e) {
            Log.w('Failed to parse repository.loadAll result: $e', tag: 'PERSIST');
          }
        }
      } catch (e) {
        Log.w('IChatRepository.loadAll failed, falling back to SharedPreferences: $e', tag: 'PERSIST');
      }
    }

    // Fallback legacy loading via SharedPreferences
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
    Log.d('[AI-chan] clearAll llamado');
    if (repository != null) {
      try {
        await repository!.clearAll();
      } catch (e) {
        Log.w('IChatRepository.clearAll failed, falling back: $e', tag: 'PERSIST');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('chat_history');
        await prefs.remove('onboarding_data');
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history');
      await prefs.remove('onboarding_data');
    }
    messages.clear();
    Log.d('[AI-chan] clearAll completado, mensajes: ${messages.length}');
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

  /// Reintenta enviar el último mensaje marcado como failed.
  /// Devuelve true si arrancó un reintento, false si no había mensajes failed.
  Future<bool> retryLastFailedMessage({void Function(String)? onError}) async {
    final idx = messages.lastIndexWhere((m) => m.sender == MessageSender.user && m.status == MessageStatus.failed);
    if (idx == -1) return false;
    final msg = messages[idx];
    // Reintentar reusando la lógica de sendMessage, pasando existingMessageIndex
    await sendMessage(
      msg.text,
      image: msg.image,
      imageMimeType: null,
      model: _selectedModel,
      onError: onError,
      existingMessageIndex: idx,
    );
    return true;
  }
}

// (Legacy IaPromiseService eliminado; PromiseService unifica la lógica de promesas)
