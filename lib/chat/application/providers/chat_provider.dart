// event detection moved into SendMessageUseCase
import 'package:ai_chan/shared/domain/services/promise_service.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/services/memory_summary_service.dart';
import 'dart:io';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/core/services/image_request_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart' show showAppSnackBar, showAppDialog;
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/voice.dart';
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;
import 'package:ai_chan/chat/domain/services/periodic_ia_message_scheduler.dart';
import 'package:ai_chan/core/services/prompt_builder.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/network_utils.dart';
import 'package:ai_chan/chat/application/use_cases/send_message_use_case.dart';

// Opciones asociadas a cada mensaje en la cola de envío diferido.
class _QueuedSendOptions {
  final String? model;
  final String? callPrompt;
  final AiImage? image;
  final String? imageMimeType;
  final String? preTranscribedText;
  final String? userAudioPath;
  _QueuedSendOptions({
    this.model,
    this.callPrompt,
    this.image,
    this.imageMimeType,
    this.preTranscribedText,
    this.userAudioPath,
  });
}

class ChatProvider extends ChangeNotifier {
  final IChatRepository? repository;
  final IAIService? aiService;
  final IChatResponseService? chatResponseService;
  SendMessageUseCase? sendMessageUseCase;

  // Allow injecting a scheduler for tests or different runtime behavior. If not
  // provided, create a default one.
  final PeriodicIaMessageScheduler _periodicScheduler;

  // Debounce timer to avoid excessive saveAll() calls when notifyListeners()
  // is triggered many times in quick succession.
  Timer? _saveDebounceTimer;
  final Duration _saveDebounceDuration = const Duration(milliseconds: 300);

  // Flag para evitar loops tras dispose
  bool _isDisposed = false;

  // ===== Cola de envío diferido =====
  // Cola de envío diferido: guardamos los localIds encolados para poder
  // actualizar su estado cuando el último se envíe. Conservamos una sola
  // estructura de opciones para el último mensaje encolado (simplifica casos).
  final List<String> _queuedMessageLocalIds = [];
  Timer? _queuedSendTimer;
  final Duration _queuedSendDelay = const Duration(seconds: 5);

  // Opciones asociadas al último mensaje encolado (null si no hay ninguno).
  _QueuedSendOptions? _queuedOptions;

  /// Número de mensajes actualmente en cola (pendientes de envío automático)
  int get queuedCount => _queuedMessageLocalIds.length;

  /// Scheduler público que la UI debe usar en lugar de llamar directamente
  /// a `sendMessage` cuando quiera la semántica de "cola + envío tras 5s".
  /// - Añade el mensaje a `messages` inmediatamente (para contexto/UX).
  /// - Si el usuario deja el input vacío durante [_queuedSendDelay], se enviará
  ///   únicamente el último mensaje en la cola. Los demás permanecerán en
  ///   `messages` y formarán parte del contexto enviado.
  void scheduleSendMessage(
    String text, {
    String? callPrompt,
    String? model,
    AiImage? image,
    String? imageMimeType,
    String? preTranscribedText,
    String? userAudioPath,
  }) {
    final now = DateTime.now();
    final bool hasImage = image != null && (((image.base64 ?? '').isNotEmpty) || ((image.url ?? '').isNotEmpty));
    final isAutomaticPrompt = text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);
    AiImage? imageForHistory;
    if (hasImage) {
      imageForHistory = AiImage(url: image.url, seed: image.seed, prompt: image.prompt);
    }
    String displayText;
    if (isAutomaticPrompt) {
      displayText = callPrompt;
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

    // Añadir a la lista de mensajes para que formen parte del contexto
    messages.add(msg);
    final lid = msg.localId;
    // Añadir a la lista de encolados (evitar duplicados por si acaso)
    if (!_queuedMessageLocalIds.contains(lid)) _queuedMessageLocalIds.add(lid);
    _queuedOptions = _QueuedSendOptions(
      model: model,
      callPrompt: callPrompt,
      image: image,
      imageMimeType: imageMimeType,
      preTranscribedText: preTranscribedText,
      userAudioPath: userAudioPath,
    );
    // Reiniciar temporizador de envío automático
    _startOrResetQueuedTimer();
    notifyListeners();
  }

  void _startOrResetQueuedTimer() {
    _queuedSendTimer?.cancel();
    if (_queuedMessageLocalIds.isEmpty) return;
    _queuedSendTimer = Timer(_queuedSendDelay, () async {
      await _processQueuedMessages();
    });
  }

  /// Procesa la cola: envía solo el último mensaje en la cola mediante
  /// `sendMessage(..., existingMessageIndex: idx)`. Los mensajes previos
  /// permanecen en `messages` y se incluyen en el prompt/contexto.
  Future<void> _processQueuedMessages() async {
    _queuedSendTimer?.cancel();
    if (_queuedMessageLocalIds.isEmpty) return;
    // Copiar los ids encolados y limpiar el estado antes de proceder para
    // evitar reentrancia.
    final queuedIds = List<String>.from(_queuedMessageLocalIds);
    _queuedMessageLocalIds.clear();
    final lastLid = queuedIds.isNotEmpty ? queuedIds.last : null;
    final opts = _queuedOptions;
    _queuedOptions = null;
    if (lastLid == null) return;
    // Buscar el índice actual del mensaje por localId
    final lastIdx = messages.indexWhere((m) => m.localId == lastLid);
    // Si por alguna razón no existe, abortar
    if (lastIdx == -1) return;
    try {
      await sendMessage(
        messages[lastIdx].text,
        existingMessageIndex: lastIdx,
        callPrompt: opts?.callPrompt,
        model: opts?.model,
        image: opts?.image,
        imageMimeType: opts?.imageMimeType,
        preTranscribedText: opts?.preTranscribedText,
        userAudioPath: opts?.userAudioPath,
      );
      // Tras un envío exitoso, sincronizar el estado de todos los mensajes
      // que estaban encolados para que tengan el mismo estado que el
      // mensaje que acabamos de enviar (por ejemplo: sent/read).
      final finalStatus = messages[lastIdx].status;
      var changed = false;
      for (final qlid in queuedIds) {
        if (qlid == lastLid) continue; // ya actualizado por sendMessage
        final idx = messages.indexWhere((m) => m.localId == qlid);
        if (idx != -1) {
          final m = messages[idx];
          if (m.sender == MessageSender.user && m.status != finalStatus) {
            messages[idx] = m.copyWith(status: finalStatus);
            changed = true;
          }
        }
      }
      if (changed) notifyListeners();
    } catch (e) {
      // sendMessage ya marca estado failed si algo va mal; nada adicional.
    }
  }

  /// Debe llamarse desde la UI cuando el usuario está escribiendo en el
  /// input. Si `text` es no vacío se cancelará el temporizador de envío
  /// automático para evitar que mensajes en cola se envíen mientras el
  /// usuario compone otro mensaje. Si `text` queda vacío se reinicia el
  /// temporizador para enviar tras [_queuedSendDelay].
  void onUserTyping(String text) {
    final empty = text.trim().isEmpty;
    if (!empty) {
      _queuedSendTimer?.cancel();
      _queuedSendTimer = null;
    } else {
      if (_queuedMessageLocalIds.isNotEmpty) {
        _startOrResetQueuedTimer();
      }
    }
  }

  ChatProvider({
    this.repository,
    this.aiService,
    this.chatResponseService,
    SendMessageUseCase? sendMessageUseCase,
    PeriodicIaMessageScheduler? periodicScheduler,
  }) : _periodicScheduler = periodicScheduler ?? PeriodicIaMessageScheduler() {
    this.sendMessageUseCase = sendMessageUseCase ?? SendMessageUseCase(injectedService: chatResponseService);
    // AudioService se inicializa perezosamente en la primera llamada (evita inicializar plugins en tests)
  }

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
  /// - Estilo oral: frases cortas (2-8 s), pausas naturales, sin monólogos.
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

  /// Variante: permitir especificar un índice concreto a actualizar.
  /// Si [index] es null se comporta como la versión sin índice (busca el último user).
  void _setLastUserMessageStatus(MessageStatus status, {int? index}) {
    if (index != null) {
      if (index >= 0 && index < messages.length) {
        // If we're marking as read, also mark all previous user messages as read
        if (status == MessageStatus.read) {
          var changed = false;
          for (var i = 0; i <= index; i++) {
            final m = messages[i];
            if (m.sender == MessageSender.user && m.status != MessageStatus.read) {
              messages[i] = m.copyWith(status: MessageStatus.read);
              changed = true;
            }
          }
          if (changed) notifyListeners();
        } else {
          final m = messages[index];
          if (m.sender == MessageSender.user) {
            if (m.status != status) {
              messages[index] = m.copyWith(status: status);
              notifyListeners();
            }
          }
        }
      }
      return;
    }
    // Fallback: aplicar al último mensaje de usuario (comportamiento previo)
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.sender == MessageSender.user) {
        if (status == MessageStatus.read) {
          // mark this and all previous user messages as read
          var changed = false;
          for (var j = 0; j <= i; j++) {
            final mm = messages[j];
            if (mm.sender == MessageSender.user && mm.status != MessageStatus.read) {
              messages[j] = mm.copyWith(status: MessageStatus.read);
              changed = true;
            }
          }
          if (changed) notifyListeners();
        } else {
          if (m.status != status) {
            messages[i] = m.copyWith(status: status);
            notifyListeners();
          }
        }
        return;
      }
    }
  }

  // Helper: detectar la etiqueta [no_reply] en el texto y, si existe,
  // resetear indicadores UI, marcar el último mensaje del usuario como
  // SENT (no read) y notificar a la UI. Devuelve true si la etiqueta fue
  // encontrada y manejada (para hacer early return en el flujo llamador).
  bool _checkAndHandleNoReply(String? text, {int? index}) {
    if (text == null) return false;
    final hasNoReply = RegExp(r'\[no_reply\]', caseSensitive: false).hasMatch(text);
    if (!hasNoReply) return false;
    Log.i('IA devolvió [no_reply]; ignorando mensaje del asistente.', tag: 'CHAT');
    // Reset indicadores y finalizar flujo limpio
    isSendingImage = false;
    isTyping = false;
    isSendingAudio = false;
    _imageRequestId++;
    // Mantener el último mensaje del usuario en SENT (no marcar como read)
    _setLastUserMessageStatus(MessageStatus.sent, index: index);
    notifyListeners();
    return true;
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
      selected = Config.requireDefaultTextModel();
    }

    // Detección de petición de imagen (solo si no es prompt automático)
    bool solicitaImagen = false;
    if (!isAutomaticPrompt) {
      final List<Message> recentUserHistory = [];
      int startIdx = messages.length - 1;
      if (messages.isNotEmpty && messages.last.sender == MessageSender.user) {
        startIdx = messages.length - 2;
      }
      for (int i = startIdx; i >= 0 && recentUserHistory.length < 5; i--) {
        final m = messages[i];
        if (m.sender == MessageSender.user && m.text.trim().isNotEmpty) {
          recentUserHistory.add(m);
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
        final cfgModel = Config.requireDefaultImageModel();
        Log.i('Solicitud de imagen detectada. Forzando modelo desde Config', tag: 'CHAT');
        selected = cfgModel;
      }
    }

  // Enviar vía servicio modularizado (maneja reintentos y base64)
  ChatResult result = ChatResult(text: '', isImage: false, imagePath: null, prompt: null, seed: null, finalModelUsed: '');
    try {
      // Antes de iniciar la petición, comprobar si hay red.
      final bool online = await hasInternetConnection();
      if (!online) {
        // Dejar el mensaje en 'sending' hasta que la conexión vuelva.
        Log.i('No hay conexión. Esperando reconexión para enviar mensaje...', tag: 'CHAT');
        // Escuchar / reintentar en background sin bloquear el UI thread.
        () async {
          while (!_isDisposed) {
            final nowOnline = await hasInternetConnection();
            if (nowOnline) break;
            await Future.delayed(const Duration(seconds: 2));
          }
          if (_isDisposed) return;
          // Cuando vuelva la conexión, iniciar el envío real (marca sent justo antes)
          _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);
          try {
            if (chatResponseService != null) {
              _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);
              final outcome = await (sendMessageUseCase ?? SendMessageUseCase(injectedService: chatResponseService))
                  .sendChat(
                recentMessages: recentMessages,
                systemPromptObj: systemPromptObj,
                model: selected,
                imageBase64: image?.base64,
                imageMimeType: imageMimeType,
                enableImageGeneration: solicitaImagen,
                onboardingData: onboardingData,
                saveAll: saveAll,
              );
              // Marcar como read inmediatamente al recibir la respuesta de la IA
              _setLastUserMessageStatus(MessageStatus.read, index: existingMessageIndex);
              if (_checkAndHandleNoReply(outcome.result.text, index: existingMessageIndex)) return;
              result = await _applySendOutcome(outcome, existingMessageIndex: existingMessageIndex);
            } else {
              // Fallback a impl vía DI
              final impl = di.getChatResponseService();
              _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);
              final outcome = await (sendMessageUseCase ?? SendMessageUseCase(injectedService: impl)).sendChat(
                recentMessages: recentMessages,
                systemPromptObj: systemPromptObj,
                model: selected,
                imageBase64: image?.base64,
                imageMimeType: imageMimeType,
                enableImageGeneration: solicitaImagen,
                onboardingData: onboardingData,
                saveAll: saveAll,
              );
              _setLastUserMessageStatus(MessageStatus.read, index: existingMessageIndex);
              if (_checkAndHandleNoReply(outcome.result.text, index: existingMessageIndex)) return;
              result = await _applySendOutcome(outcome, existingMessageIndex: existingMessageIndex);
            }
          } catch (e) {
            Log.e('Error enviando mensaje tras reconexión', tag: 'CHAT', error: e);
            final idx = messages.lastIndexWhere((m) => m.sender == MessageSender.user);
            if (idx != -1) {
              messages[idx] = messages[idx].copyWith(status: MessageStatus.failed);
              notifyListeners();
            }
          }
        }();
        // Salir del flujo principal: el envío se gestionará en background al reconectar
        return;
      }

      if (chatResponseService != null) {
        // Delegate to SendMessageUseCase (keeps conversion centralized)
        _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);
  final outcome = await (sendMessageUseCase ?? SendMessageUseCase(injectedService: chatResponseService)).sendChat(
          recentMessages: recentMessages,
          systemPromptObj: systemPromptObj,
          model: selected,
          imageBase64: image?.base64,
          imageMimeType: imageMimeType,
          enableImageGeneration: solicitaImagen,
        onboardingData: onboardingData,
        saveAll: saveAll,
        );
  if (_checkAndHandleNoReply(outcome.result.text, index: existingMessageIndex)) return;
  _setLastUserMessageStatus(MessageStatus.read, index: existingMessageIndex);
  result = outcome.result;
        messages.add(outcome.assistantMessage);
        if (outcome.assistantMessage.text.trim() == '[call][/call]') {
          pendingIncomingCallMsgIndex = messages.length - 1;
          Log.i('[Call] Placeholder de llamada entrante detectado (index=$pendingIncomingCallMsgIndex)', tag: 'CHAT');
          notifyListeners();
        }
        try {
          if (outcome.ttsRequested) await generateTtsForMessage(outcome.assistantMessage);
        } catch (_) {}
        if (outcome.updatedProfile != null) {
          onboardingData = outcome.updatedProfile!;
          _events
            ..clear()
            ..addAll(onboardingData.events ?? []);
        }
      } else {
        // Resolver una implementación por medio de la fábrica DI y usar la interfaz
        final impl = di.getChatResponseService();
        // Marcar inmediatamente como 'sent' antes del await para que el mensaje
        // del usuario no quede en estado 'sending' mientras la operación
        // de generación de imágenes (o procesamiento largo) se completa.
        _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);

        // Use unified SendMessageUseCase for DI fallback as well
  final outcome = await (sendMessageUseCase ?? SendMessageUseCase(injectedService: impl)).sendChat(
          recentMessages: recentMessages,
          systemPromptObj: systemPromptObj,
          model: selected,
          imageBase64: image?.base64,
          imageMimeType: imageMimeType,
          enableImageGeneration: solicitaImagen,
          onboardingData: onboardingData,
          saveAll: saveAll,
        );
        // Si la IA devuelve el marcador [no_reply], ignorar la respuesta y
        // asegurarnos de NO activar indicadores como isTyping.
  if (_checkAndHandleNoReply(outcome.result.text, index: existingMessageIndex)) return;
  // Marcar como read inmediatamente al recibir la respuesta de la IA
  _setLastUserMessageStatus(MessageStatus.read, index: existingMessageIndex);
  result = outcome.result;
        messages.add(outcome.assistantMessage);
        if (outcome.assistantMessage.text.trim() == '[call][/call]') {
          pendingIncomingCallMsgIndex = messages.length - 1;
          Log.i('[Call] Placeholder de llamada entrante detectado (index=$pendingIncomingCallMsgIndex)', tag: 'CHAT');
          notifyListeners();
        }
        try {
          if (outcome.ttsRequested) await generateTtsForMessage(outcome.assistantMessage);
        } catch (_) {}
        if (outcome.updatedProfile != null) {
          onboardingData = outcome.updatedProfile!;
          _events
            ..clear()
            ..addAll(onboardingData.events ?? []);
        }
        notifyListeners();
      }
      // Éxito de red: marcar último mensaje usuario como 'sent'
      _setLastUserMessageStatus(MessageStatus.sent, index: existingMessageIndex);
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
      final int idx =
          (existingMessageIndex != null && existingMessageIndex >= 0 && existingMessageIndex < messages.length)
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
    _setLastUserMessageStatus(MessageStatus.read, index: existingMessageIndex);

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
  // Si la IA responde con el marcador [no_reply'], no añadir ni procesar la respuesta
  // (el post-procesado - TTS / eventos - lo realiza SendMessageUseCase y se
  // aplica cuando se añadió el assistantMessage en las ramas de envío).

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
  IAudioChatService? _audioService;

  IAudioChatService get audioService => _audioService ??= di.getAudioChatService(
    onStateChanged: () => notifyListeners(),
    onWaveform: (_) => notifyListeners(),
  );

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

    // Intentar transcripci f3n con reintentos. Antes la implementaci f3n solo
    // incrementaba el contador en errores, provocando un bucle infinito cuando
    // la API devolv eda "null" sin lanzar excepciones. Ahora iteramos un n famax
    // de intentos y siempre incrementamos el contador entre intentos.
    const maxRetries = 2;
    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        final stt = di.getSttService();
        final result = await stt.transcribeAudio(path);
        if (result != null && result.trim().isNotEmpty) {
          transcript = result.trim();
          Log.i('Transcripci f3n exitosa en intento ${attempt + 1}', tag: 'AUDIO');
          break;
        } else {
          Log.w('Transcripci f3n vac eda en intento ${attempt + 1}', tag: 'AUDIO');
        }
      } catch (e) {
        Log.e('Error transcribiendo (intento ${attempt + 1}/$maxRetries)', tag: 'AUDIO', error: e);
      }

      attempt++;
      if (attempt <= maxRetries) {
        // Backoff progresivo entre intentos
        await Future.delayed(Duration(milliseconds: 500 * attempt));
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

  Future<void> togglePlayAudio(Message msg, [BuildContext? context]) async {
    // Prefer using the app-wide snack helper so tests / conventions rely on
    // the centralized implementation (Overlay or root messenger).
    try {
      await audioService.togglePlay(msg, () => notifyListeners());
    } catch (e, st) {
      try {
        debugPrint('[Audio] togglePlayAudio error: $e\n$st');
      } catch (_) {}
      try {
        // Use the centralized helper which resolves a safe context internally.
        showAppSnackBar('Error: no se pudo reproducir el audio. Recurso no encontrado.', isError: true);
      } catch (_) {}
    }
  }

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
    // Resolve preferred voice according to currently selected provider (prefs -> env)
    String preferredVoice = voice;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProvider = prefs.getString('selected_audio_provider') ?? Config.getAudioProvider().toLowerCase();
      final providerKey = 'selected_voice_$savedProvider';
      final providerVoice = prefs.getString(providerKey);
      final legacyVoice = prefs.getString('selected_voice');
      if (providerVoice != null && providerVoice.trim().isNotEmpty) {
        preferredVoice = providerVoice;
      } else if (legacyVoice != null && legacyVoice.trim().isNotEmpty) {
        preferredVoice = legacyVoice;
      }
    } catch (_) {}

    final file = await audioService.synthesizeTts(msg.text, voice: preferredVoice, languageCode: lang);
    if (file != null) {
      // Ensure the synthesized file is persisted to the configured local audio dir
      try {
        final localDir = await audio_utils.getLocalAudioDir();
        String finalPath = file.path;
        if (!file.path.startsWith(localDir.path)) {
          final ext = file.path.split('.').last;
          final dest = '${localDir.path}/assistant_tts_${DateTime.now().millisecondsSinceEpoch}.$ext';
          try {
            await file.rename(dest);
            finalPath = dest;
          } catch (e) {
            try {
              await file.copy(dest);
              final srcLen = await file.length();
              final dstLen = await File(dest).length();
              if (srcLen == dstLen) {
                try {
                  await file.delete();
                } catch (_) {}
              }
              finalPath = dest;
            } catch (e2) {
              // If copy also fails, keep original file path
              debugPrint('[Audio][TTS] Could not move synthesized file to local audio dir: $e2');
            }
          }
        }

        final idx = messages.indexOf(msg);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(isAudio: true, audioPath: finalPath, autoTts: true);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[Audio][TTS] Error persisting synthesized file: $e');
        final idx = messages.indexOf(msg);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(isAudio: true, audioPath: file.path, autoTts: true);
          notifyListeners();
        }
      }
    }
  }
  // =======================================================

  /// Aplica un SendMessageOutcome: añade el assistantMessage a la lista,
  /// dispara TTS si corresponde, actualiza onboardingData y devuelve el
  /// ChatResult para continuar el flujo.
  Future<ChatResult> _applySendOutcome(SendMessageOutcome outcome, {int? existingMessageIndex}) async {
    final ChatResult chatResult = outcome.result;
    messages.add(outcome.assistantMessage);
    // Si la IA responde con el marcador [call][/call] notificar inmediatamente
    if (outcome.assistantMessage.text.trim() == '[call][/call]') {
      pendingIncomingCallMsgIndex = messages.length - 1;
      Log.i('[Call] Placeholder de llamada entrante detectado (index=$pendingIncomingCallMsgIndex)', tag: 'CHAT');
      notifyListeners();
    }
    // Generar TTS si la use-case lo solicitó
    try {
      if (outcome.ttsRequested) await generateTtsForMessage(outcome.assistantMessage);
    } catch (_) {}
    // Actualizar onboardingData si la use-case guardó/actualizó eventos
    if (outcome.updatedProfile != null) {
      onboardingData = outcome.updatedProfile!;
      _events
        ..clear()
        ..addAll(onboardingData.events ?? []);
    }
    notifyListeners();
    return chatResult;
  }

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
      if (pendingIncomingCallMsgIndex == placeholderIndex) {
        pendingIncomingCallMsgIndex = null;
      }
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
  Future<List<String>> getAllModels({bool forceRefresh = false}) async {
    return await getAllAIModels(forceRefresh: forceRefresh);
  }

  // Devuelve el servicio IA desacoplado según el modelo
  final Map<String, AIService> _services = {};

  AIService? getServiceForModel(String modelId) {
    if (_services.containsKey(modelId)) {
      return _services[modelId];
    }
    // Use centralized DI factory to obtain the IA service implementation
    final service = di.getAIServiceForModel(modelId);
    if (service is AIService) {
      _services[modelId] = service as AIService;
      return _services[modelId];
    }
    return null;
  }

  TimelineEntry? superbloqueEntry;
  // Generador de apariencia desacoplado
  final IAAppearanceGenerator iaAppearanceGenerator = IAAppearanceGenerator();

  /// Ejecuta un único intento del flujo: generar avatar a partir de la apariencia existente -> persistir
  /// Si [replace] es false, añade el avatar al historial y crea un mensaje system notificándolo.
  /// No realiza reintentos adicionales: los generadores internos ya aplican retry.
  Future<void> createAvatarFromAppearance({required bool replace, bool showErrorDialog = true}) async {
    // This method only generates the avatar from an existing appearance.
    // Appearance generation must be done separately via IAAppearanceGenerator.
    final bio = onboardingData;
    if (bio.appearance.isEmpty) {
      throw Exception('Falta la apariencia en el perfil. Genera la apariencia primero.');
    }

    // La lógica de aplicación/persistencia se implementa en el método de clase
    // `_applyAvatarAndPersist` para evitar warnings de identificadores locales
    // y mejorar testabilidad.

    try {
      final avatar = await IAAvatarGenerator().generateAvatarWithRetries(bio, appendAvatar: !replace, maxAttempts: 3);
      await _applyAvatarAndPersist(avatar, replace: replace);
    } catch (e) {
      // Si la generación con los intentos internos falló, preguntar al usuario si quiere reintentar
      if (showErrorDialog) {
        final choice = await showRegenerateAppearanceErrorDialog(e);
        if (choice == 'retry') {
          try {
            final avatar2 = await IAAvatarGenerator().generateAvatarWithRetries(
              bio,
              appendAvatar: !replace,
              maxAttempts: 3,
            );
            await _applyAvatarAndPersist(avatar2, replace: replace);
          } catch (e2) {
            Log.w('Reintento manual de generación de avatar falló: $e2', tag: 'CHAT');
            rethrow;
          }
        } else {
          rethrow;
        }
      } else {
        // Re-lanzar para que el llamador (UI) decida cómo mostrar el error y evitar duplicados
        rethrow;
      }
    }
  }

  // Aplica el avatar al perfil y persiste los cambios. Método privado de clase
  // para evitar definiciones locales que incumplen lint de identificadores.
  Future<void> _applyAvatarAndPersist(AiImage avatar, {required bool replace}) async {
    if (replace) {
      onboardingData = onboardingData.copyWith(avatars: [avatar]);
    } else {
      onboardingData = onboardingData.copyWith(avatars: [...(onboardingData.avatars ?? []), avatar]);
      try {
        final sysMsg = Message(
          text: 'Se ha añadido un nuevo avatar al historial.',
          sender: MessageSender.system,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
        );
        messages.add(sysMsg);
      } catch (_) {}
    }
    await saveAll();
    notifyListeners();
  }

  /// Nuevo nombre: Regenera la apariencia (JSON) usando IAAppearanceGenerator
  /// y, SIEMPRE, genera un nuevo avatar reemplazando los actuales.
  /// - Si [persist] es true, guarda el perfil y notifica listeners.
  /// - Muestra el diálogo centralizado en caso de error y ofrece reintento.
  Future<void> regenerateAppearance({bool persist = true}) async {
    try {
      await _doGenerateAppearanceAndReplaceAvatar(persist: persist);
    } catch (e) {
      Log.w('Error generando apariencia: $e', tag: 'CHAT');
      final choice = await showRegenerateAppearanceErrorDialog(e);
      if (choice == 'retry') {
        try {
          await _doGenerateAppearanceAndReplaceAvatar(persist: persist);
        } catch (e2) {
          Log.w('Reintento manual de generar apariencia falló: $e2', tag: 'CHAT');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  // Helper privado que realiza un único intento de generar la apariencia,
  // persistirla y luego generar el avatar reemplazando los existentes.
  Future<void> _doGenerateAppearanceAndReplaceAvatar({bool persist = true}) async {
    final appearanceMap = await iaAppearanceGenerator.generateAppearancePrompt(onboardingData);
    onboardingData = onboardingData.copyWith(appearance: appearanceMap);
    if (persist) {
      await saveAll();
      notifyListeners();
    }
    // Tras una generación exitosa de la apariencia, siempre intentar generar
    // el avatar y reemplazar los actuales. No mostramos el diálogo de error
    // interno aquí para evitar duplicados en la UX: que el llamador/UI
    // controle cómo presentar errores.
    try {
      await createAvatarFromAppearance(replace: true, showErrorDialog: false);
    } catch (_) {
      // No bloquear el flujo de apariencia si la generación de avatar falla.
    }
  }

  /// Genera únicamente un avatar a partir de la apariencia existente.
  /// Wrapper con nombre claro que delega en regenerateAppearanceOnce (que ya
  /// contiene la lógica de reintentos y diálogo). [replace] indica si
  /// reemplaza el historial (true) o añade al historial (false).
  Future<void> generateAvatarFromAppearance({required bool replace}) async {
    await createAvatarFromAppearance(replace: replace);
  }

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
    // Limpiar cualquier estado de cola previo para evitar índices obsoletos
    _clearQueuedState();
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

  /// Muestra un diálogo de error centrado para errores de regeneración
  /// y devuelve la elección del usuario: 'retry' o 'cancel' o null.
  Future<String?> showRegenerateAppearanceErrorDialog(Object error) async {
    try {
      return await showAppDialog<String>(
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('No se pudo regenerar la apariencia', style: TextStyle(color: AppColors.secondary)),
          content: SingleChildScrollView(
            child: Text(error.toString(), style: const TextStyle(color: AppColors.primary)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('retry'),
              child: const Text('Reintentar', style: TextStyle(color: AppColors.secondary)),
            ),
          ],
        ),
      );
    } catch (e) {
      Log.w('No se pudo mostrar el diálogo de regeneración: $e', tag: 'CHAT');
      return null;
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
    // Chequear generación semanal de avatar en background: si el último avatar tiene más de 7 días
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final sevenDays = Duration(days: 7).inMilliseconds;
      final lastAvatarCreatedMs = onboardingData.avatar?.createdAtMs;
      final seed = onboardingData.avatar?.seed;
      if (seed != null && seed.isNotEmpty && lastAvatarCreatedMs != null && (nowMs - lastAvatarCreatedMs) > sevenDays) {
        // Ejecutar generación asíncrona sin bloquear el loadAll() final
        () async {
          try {
            final appearanceMap = await iaAppearanceGenerator.generateAppearancePrompt(onboardingData);
            // Generate a new avatar using the same seed (append), but for weekly regen we want
            // to make it the current avatar; we append then set avatars to the new one.
            // Generate using same seed but replace the current avatars (weekly regeneration)
            final updatedProfile = onboardingData.copyWith(appearance: appearanceMap);
            final avatar = await IAAvatarGenerator().generateAvatarWithRetries(
              updatedProfile,
              appendAvatar: true,
              maxAttempts: 3,
            );
            onboardingData = onboardingData.copyWith(avatars: [avatar]);
            // Insertar un mensaje system para que la IA tenga consciencia de la actualización
            try {
              final sysMsg = Message(
                text: 'Tu avatar se ha actualizado. Usa la nueva imagen como referencia en futuras respuestas.',
                sender: MessageSender.system,
                dateTime: DateTime.now(),
                status: MessageStatus.read,
              );
              messages.add(sysMsg);
            } catch (_) {}
            await saveAll();
            notifyListeners();
          } catch (e) {
            Log.w('Error generando avatar semanal en background: $e', tag: 'CHAT');
            // Mostrar diálogo de error centralizado y permitir reintento manual
            try {
              final choice = await showRegenerateAppearanceErrorDialog(e);
              if (choice == 'retry') {
                try {
                  final appearanceMap2 = await iaAppearanceGenerator.generateAppearancePrompt(onboardingData);
                  final updatedProfile2 = onboardingData.copyWith(appearance: appearanceMap2);
                  final avatar2 = await IAAvatarGenerator().generateAvatarWithRetries(
                    updatedProfile2,
                    appendAvatar: true,
                    maxAttempts: 3,
                  );
                  onboardingData = onboardingData.copyWith(avatars: [avatar2]);
                  try {
                    final sysMsg2 = Message(
                      text: 'Tu avatar se ha actualizado. Usa la nueva imagen como referencia en futuras respuestas.',
                      sender: MessageSender.system,
                      dateTime: DateTime.now(),
                      status: MessageStatus.read,
                    );
                    messages.add(sysMsg2);
                  } catch (_) {}
                  await saveAll();
                  notifyListeners();
                } catch (e2) {
                  Log.w('Error reintentando avatar semanal: $e2', tag: 'CHAT');
                }
              }
            } catch (_) {}
          }
        }();
      }
    } catch (_) {}
    await loadSelectedModel();
    // Reprogramar promesas IA futuras desde events
    _promiseService.restoreFromEvents();
    notifyListeners();
    // Nota: no arrancar el scheduler automáticamente al cargar; el caller/UI
    // debe decidir cuándo iniciar el envío periódico. Esto mejora testeo y
    // evita side-effects durante carga.
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
    // Limpiar cola de envío diferido
    _clearQueuedState();
    Log.d('[AI-chan] clearAll completado, mensajes: ${messages.length}');
    notifyListeners();
  }

  /// Limpia el estado interno de la cola de envío diferido.
  void _clearQueuedState() {
    _queuedSendTimer?.cancel();
    _queuedSendTimer = null;
    _queuedMessageLocalIds.clear();
    _queuedOptions = null;
  }

  /// Fuerza el procesamiento inmediato de la cola (útil para un botón "Enviar ahora").
  Future<void> flushQueuedMessages() async {
    // Cancelar timer y procesar inmediatamente
    _queuedSendTimer?.cancel();
    _queuedSendTimer = null;
    await _processQueuedMessages();
  }

  @override
  void notifyListeners() {
    // Debounce persistence to avoid excessive disk writes when many state
    // updates happen quickly (e.g., during message streaming).
    saveAllEvents();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(_saveDebounceDuration, () {
      saveAll();
    });
    super.notifyListeners();
  }

  Future<void> saveAllEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = jsonEncode(_events.map((e) => e.toJson()).toList());
    await prefs.setString(_eventsKey, eventsJson);
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      audioService.dispose();
    } catch (_) {}
    _saveDebounceTimer?.cancel();
    _queuedSendTimer?.cancel();
    try {
      _periodicScheduler.stop();
    } catch (_) {}
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
