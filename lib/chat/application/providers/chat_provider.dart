import 'package:ai_chan/shared/domain/services/promise_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:ai_chan/shared/utils/provider_persist_utils.dart';
import 'package:ai_chan/shared/utils/audio_duration_utils.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/services/memory_summary_service.dart';
import 'dart:io';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/chat/application/utils/avatar_persist_utils.dart';
import 'package:ai_chan/core/services/image_request_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart'
    show showAppSnackBar, showAppDialog;
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/chat/application/services/tts_service.dart';
import 'package:ai_chan/chat/domain/services/periodic_ia_message_scheduler.dart';
import 'package:ai_chan/core/services/prompt_builder.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/network_utils.dart';
import 'package:ai_chan/chat/application/use_cases/send_message_use_case.dart';
import 'package:ai_chan/shared/mixins/debounced_persistence_mixin.dart';
import 'package:ai_chan/chat/application/services/message_queue_manager.dart';
import 'package:ai_chan/chat/application/services/memory_manager.dart';
import 'package:ai_chan/shared/utils/backup_auto_uploader.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/chat/application/services/timeline_updater.dart';

// Using external MessageQueueManager. Queue options type lives in the
// message_queue_manager service (QueuedSendOptions).

class ChatProvider extends ChangeNotifier with DebouncedPersistenceMixin {
  final IChatRepository? repository;
  final AIService? aiService;
  SendMessageUseCase? sendMessageUseCase;
  TtsService? ttsService;

  // Allow injecting a scheduler for tests or different runtime behavior. If not
  // provided, create a default one.
  final PeriodicIaMessageScheduler _periodicScheduler;

  // Flag para evitar loops tras dispose
  bool _isDisposed = false;

  // Queue manager handling delayed automatic sends
  MessageQueueManager? _queueManager;

  // Optional injected MemoryManager to allow tests to control memory processing
  final MemoryManager? memoryManager;

  // Typing/audio timing configuration (words per minute and clamps)
  final int typingWpm;
  final int typingMinMs;
  final int typingMaxMs;

  /// Número de mensajes actualmente en cola (pendientes de envío automático)
  int get queuedCount => _queueManager?.queuedCount ?? 0;

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
    final result = _createMessageWithValidation(
      text: text,
      preTranscribedText: preTranscribedText,
      callPrompt: callPrompt,
      dateTime: now,
      image: image,
      userAudioPath: userAudioPath,
    );

    if (result.shouldAdd) {
      messages.add(result.message);
      final lid = result.message.localId;
      // Encolar y dejar que MessageQueueManager controle el temporizador
      final opts = QueuedSendOptions(
        model: model,
        callPrompt: callPrompt,
        image: image,
        imageMimeType: imageMimeType,
        preTranscribedText: preTranscribedText,
        userAudioPath: userAudioPath,
      );
      _queueManager?.enqueue(lid, options: opts);
      notifyListeners();
    }
  }

  // Queue processing is handled by MessageQueueManager; no local implementation.

  /// Debe llamarse desde la UI cuando el usuario está escribiendo en el
  /// input. Si `text` es no vacío se cancelará el temporizador de envío
  /// automático para evitar que mensajes en cola se envíen mientras el
  /// usuario compone otro mensaje. Si `text` queda vacío se reinicia el
  /// temporizador para enviar tras [_queuedSendDelay].
  void onUserTyping(String text) {
    final empty = text.trim().isEmpty;
    if (!empty) {
      _queueManager?.cancelTimer();
    } else {
      if (queuedCount > 0) {
        _queueManager?.ensureTimer();
      }
    }
  }

  ChatProvider({
    this.repository,
    this.aiService,
    SendMessageUseCase? sendMessageUseCaseParam,
    TtsService? ttsServiceParam,
    PeriodicIaMessageScheduler? periodicScheduler,
    MemoryManager? memoryManagerParam,
    int? typingWpm,
    int? typingMinMs,
    int? typingMaxMs,
  }) : sendMessageUseCase = sendMessageUseCaseParam ?? SendMessageUseCase(),
       ttsService = ttsServiceParam,
       _periodicScheduler = periodicScheduler ?? PeriodicIaMessageScheduler(),
       memoryManager = memoryManagerParam,
       typingWpm = typingWpm ?? 300,
       typingMinMs = typingMinMs ?? 400,
       typingMaxMs = typingMaxMs ?? 10000 {
    // Initialize helpers with sensible defaults.
    initDebouncedPersistence(saveAll);

    // Queue manager: when the timer flushes, send only the last queued message
    // and mark earlier queued messages as 'sent' so they don't remain in 'sending'.
    _queueManager = MessageQueueManager(
      onFlush: (ids, lastLocalId, options) {
        try {
          // Mark all but last as sent (they serve as context)
          for (final lid in ids) {
            if (lid == lastLocalId) continue;
            final idx = messages.indexWhere((m) => m.localId == lid);
            if (idx != -1) {
              final m = messages[idx];
              if (m.sender == MessageSender.user &&
                  m.status == MessageStatus.sending) {
                messages[idx] = m.copyWith(status: MessageStatus.sent);
              }
            }
          }

          // Find index of last message and trigger sendMessage reusing that index.
          final lastIdx = messages.indexWhere((m) => m.localId == lastLocalId);
          if (lastIdx != -1) {
            final lastMsg = messages[lastIdx];
            // Mark last message as 'sent' immediately to avoid UI stuck in 'sending'
            if (lastMsg.sender == MessageSender.user &&
                lastMsg.status == MessageStatus.sending) {
              messages[lastIdx] = lastMsg.copyWith(status: MessageStatus.sent);
              try {
                // notify UI about state change
                notifyListeners();
              } catch (_) {}
            }
            // Fire-and-forget send; existingMessageIndex ensures we reuse the placeholder
            sendMessage(
              lastMsg.text,
              model: options?.model,
              callPrompt: options?.callPrompt,
              image: options?.image as AiImage?,
              imageMimeType: options?.imageMimeType,
              preTranscribedText: options?.preTranscribedText,
              userAudioPath: options?.userAudioPath,
              existingMessageIndex: lastIdx,
            );
          }
        } catch (e, st) {
          Log.w('Error flushing queued messages: $e \n$st', tag: 'CHAT');
        }
      },
    );
  }

  void startPeriodicIaMessages() {
    _periodicScheduler.start(
      profileGetter: () => onboardingData,
      messagesGetter: () => messages,
      triggerSend: (prompt, model) =>
          sendMessage('', callPrompt: prompt, model: model),
    );
  }

  // Lógica de horarios / periodicidad movida a PeriodicIaMessageScheduler & ScheduleUtils

  /// Detener el envío automático de mensajes IA
  void stopPeriodicIaMessages() => _periodicScheduler.stop();

  final PromptBuilder _promptBuilder = PromptBuilder();

  String buildRealtimeSystemPromptJson({int maxRecent = 32}) =>
      _promptBuilder.buildRealtimeSystemPromptJson(
        profile: onboardingData,
        messages: messages,
        maxRecent: maxRecent,
      );

  /// Construye un SystemPrompt (JSON) específico para llamadas de voz.
  /// Reutiliza el mismo perfil, timeline y últimos [maxRecent] mensajes,
  /// pero con instrucciones adaptadas a la modalidad de llamada:
  /// - No pedir/ofrecer fotos ni imágenes durante la llamada.
  /// - No usar enlaces/URLs, clics, Markdown, ni hablar de herramientas.
  /// - Estilo oral: frases cortas (2-8 s), pausas naturales, sin monólogos.
  /// - No presentarse como "asistente" o "IA"; mantener la misma persona del chat.
  String buildCallSystemPromptJson({
    int maxRecent = 32,
    required bool aiInitiatedCall,
  }) => _promptBuilder.buildCallSystemPromptJson(
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

  late final PromiseService _promiseService = PromiseService(
    events: _events,
    onEventsChanged: () => notifyListeners(),
    sendSystemPrompt: (text, {String? callPrompt, String? model}) =>
        sendMessage(text, callPrompt: callPrompt, model: model),
  );
  void schedulePromiseEvent(EventEntry e) =>
      _promiseService.schedulePromiseEvent(e);
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
            if (m.sender == MessageSender.user &&
                m.status != MessageStatus.read) {
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
            if (mm.sender == MessageSender.user &&
                mm.status != MessageStatus.read) {
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
    final hasNoReply = RegExp(
      r'\[no_reply\]',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasNoReply) return false;
    Log.i(
      'IA devolvió [no_reply]; ignorando mensaje del asistente.',
      tag: 'CHAT',
    );
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
    final messageData = _createMessageWithValidation(
      text: text,
      preTranscribedText: preTranscribedText,
      callPrompt: callPrompt,
      dateTime: now,
      image: image,
      userAudioPath: userAudioPath,
    );
    final bool hasImage =
        image != null &&
        (((image.base64 ?? '').isNotEmpty) || ((image.url ?? '').isNotEmpty));
    final isAutomaticPrompt =
        text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);

    if (messageData.shouldAdd) {
      if (existingMessageIndex != null &&
          existingMessageIndex >= 0 &&
          existingMessageIndex < messages.length) {
        // Reintento: sobrescribir estado del mensaje existente en lugar de añadir uno nuevo
        messages[existingMessageIndex] = messages[existingMessageIndex]
            .copyWith(
              status: MessageStatus.sending,
              text: messageData.message.text,
              image: messageData.message.image,
              isAudio: messageData.message.isAudio,
              audio: messageData.message.audio,
            );
      } else {
        messages.add(messageData.message);
      }
      if (userAudioPath != null) {
        try {
          final f = File(userAudioPath);
          Log.d(
            'Audio: sendMessage added msg con audioPath=$userAudioPath exists=${f.existsSync()} size=${f.existsSync() ? f.lengthSync() : 0}',
            tag: 'AUDIO',
          );
        } catch (_) {}
      }

      // Calcular duración del audio del usuario en segundo plano
      if (messageData.message.audio?.url != null &&
          messageData.message.audio!.url!.isNotEmpty) {
        _calculateUserAudioDuration(messageData.message);
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
      solicitaImagen = ImageRequestService.isImageRequested(
        text: text,
        history: recentUserHistory,
      );
    }
    // Si el usuario adjuntó una imagen, NO considerarlo como petición para que la IA genere
    // una nueva imagen: estamos enviando la imagen del usuario para analizarla.
    if (hasImage) {
      solicitaImagen = false;
      Log.i(
        'Imagen adjunta por el usuario: omitiendo detección de solicitud de imagen.',
        tag: 'CHAT',
      );
    }
    if (solicitaImagen) {
      final lower = selected.toLowerCase();
      if (!lower.startsWith('gpt-')) {
        final cfgModel = Config.requireDefaultImageModel();
        Log.i(
          'Solicitud de imagen detectada. Forzando modelo desde Config',
          tag: 'CHAT',
        );
        selected = cfgModel;
      }
    }

    // Enviar vía servicio modularizado (maneja reintentos y base64)
    ChatResult result = ChatResult(
      text: '',
      isImage: false,
      imagePath: null,
      prompt: null,
      seed: null,
      finalModelUsed: '',
    );

    // Guardamos el SendMessageOutcome temporalmente para aplicarlo
    // tras mostrar los indicadores (typing / sending image / audio).
    SendMessageOutcome? pendingOutcome;

    // Helper: calcular delay en ms basado en número de palabras (WPM).
    // Use a human-like default speaking rate and cap at 30s.
    // Pondré 300 palabras por minuto, que es aproximadamente el record mundial.
    int computeDelayMsFromText(
      String text, {
      int wpm = 300,
      int minMs = 400,
      int maxMs = 10000,
    }) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return minMs;
      final words = trimmed.split(RegExp(r'\s+')).length;
      final perWord = (60000 / wpm).round();
      final ms = words * perWord;
      return ms.clamp(minMs, maxMs).toInt();
    }

    // Helper local: aplica el outcome luego del delay calculado en base al texto.
    Future<void> finalizeAssistantResponse() async {
      final SendMessageOutcome? localOutcome = pendingOutcome;
      if (localOutcome == null) return;
      // Consume shared pendingOutcome immediately to avoid races
      pendingOutcome = null;
      final ChatResult res = localOutcome.result;

      // Calcular delay en ms según número de palabras (typing / audio)
      final delayMs = computeDelayMsFromText(res.text);
      try {
        await Future.delayed(Duration(milliseconds: delayMs));
      } catch (_) {
        // Si falla el delay por cancelación, continuar de todos modos
      }

      // Si se ha disposed, abortar
      if (_isDisposed) return;

      try {
        // Añadir el assistantMessage, generar TTS y actualizar perfil/eventos
        await _applySendOutcome(
          localOutcome,
          existingMessageIndex: existingMessageIndex,
        );
      } catch (e, st) {
        Log.w('Error applying pending outcome: $e\n$st', tag: 'CHAT');
      }

      // Ejecutar acciones posteriores al mensaje IA (igual que antes)
      try {
        onIaMessageSent();
      } catch (_) {}

      isSendingImage = false;
      isTyping = false;
      // Mantener isSendingAudio=true hasta que el audio (TTS) esté verdaderamente
      // persistido y asociado al mensaje (audioPath). No lo reseteamos aquí.
      _imageRequestId++;

      final textResp = res.text;
      if (textResp.trim() != '' &&
          !textResp.trim().toLowerCase().contains(
            'error al conectar con la ia',
          ) &&
          !textResp.trim().toLowerCase().contains('"error"')) {
        try {
          final memManager =
              memoryManager ?? MemoryManager(profile: onboardingData);
          final oldLevel0Keys = (onboardingData.timeline)
              .where((t) => t.level == 0)
              .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
              .toSet();
          final memResult = await memManager.processAllSummariesAndSuperblock(
            messages: messages,
            timeline: onboardingData.timeline,
            superbloqueEntry: superbloqueEntry,
          );
          onboardingData = TimelineUpdater.applyTimelineUpdate(
            profile: onboardingData,
            timeline: memResult.timeline,
            superbloqueEntry: memResult.superbloqueEntry,
          );
          superbloqueEntry = memResult.superbloqueEntry;
          if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, memResult.timeline)) {
            Log.d(
              'Auto-backup: trigger scheduled (post-finalizeAssistantResponse) — new summary block detected',
              tag: 'BACKUP_AUTO',
            );
            unawaited(_maybeTriggerAutoBackup());
          } else {
            Log.d(
              'Auto-backup: no new level-0 blocks; skip trigger (post-finalizeAssistantResponse)',
              tag: 'BACKUP_AUTO',
            );
          }
        } catch (e) {
          Log.w(
            '[AI-chan][WARN] Falló actualización de memoria post-IA (finalize): $e',
          );
        }
      }

      // Evitar doble render si el assistantMessage era placeholder de llamada
      if (localOutcome.assistantMessage.text.trim() != '[call][/call]') {
        try {
          notifyListeners();
        } catch (_) {}
      }
    }

    try {
      // Antes de iniciar la petición, comprobar si hay red.
      final bool online = await hasInternetConnection();
      if (!online) {
        // Dejar el mensaje en 'sending' hasta que la conexión vuelva.
        Log.i(
          'No hay conexión. Esperando reconexión para enviar mensaje...',
          tag: 'CHAT',
        );
        // Escuchar / reintentar en background sin bloquear el UI thread.
        () async {
          while (!_isDisposed) {
            final nowOnline = await hasInternetConnection();
            if (nowOnline) break;
            await Future.delayed(const Duration(seconds: 2));
          }
          if (_isDisposed) return;
          // Cuando vuelva la conexión, iniciar el envío real (marca sent justo antes)
          _setLastUserMessageStatus(
            MessageStatus.sent,
            index: existingMessageIndex,
          );
          try {
            _setLastUserMessageStatus(
              MessageStatus.sent,
              index: existingMessageIndex,
            );
            final outcome = await (sendMessageUseCase ?? SendMessageUseCase())
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
            _setLastUserMessageStatus(
              MessageStatus.read,
              index: existingMessageIndex,
            );
            if (_checkAndHandleNoReply(
              outcome.result.text,
              index: existingMessageIndex,
            )) {
              return;
            }
            try {
              final outRes = outcome.result;
              isTyping = !outRes.isImage;
              isSendingImage = outRes.isImage;
              // Usar la señal del use-case para saber si se debe sintetizar audio
              if (outcome.ttsRequested) isSendingAudio = true;
              notifyListeners();
            } catch (_) {}
            // Guardar outcome y mostrar indicadores; la adición del mensaje
            // se realizará tras el delay por _finalizeAssistantResponse.
            pendingOutcome = outcome;
            result = outcome.result;
            try {
              final outRes = outcome.result;
              isTyping = !outRes.isImage;
              isSendingImage = outRes.isImage;
              // Use the use-case signal (outcome.ttsRequested) to set audio indicator.
              notifyListeners();
            } catch (_) {}
            // Lanzar finalizer (no await) para aplicar outcome tras el delay
            finalizeAssistantResponse();
          } catch (e) {
            Log.e(
              'Error enviando mensaje tras reconexión',
              tag: 'CHAT',
              error: e,
            );
            final idx = messages.lastIndexWhere(
              (m) => m.sender == MessageSender.user,
            );
            if (idx != -1) {
              messages[idx] = messages[idx].copyWith(
                status: MessageStatus.failed,
              );
              notifyListeners();
            }
          }
        }();
        // Salir del flujo principal: el envío se gestionará en background al reconectar
        return;
      }

      // Preferir SendMessageUseCase (por defecto usa AIService) para mantener
      // comportamiento centralizado y permitir testOverride en tests.
      _setLastUserMessageStatus(
        MessageStatus.sent,
        index: existingMessageIndex,
      );
      final outcome = await (sendMessageUseCase ?? SendMessageUseCase())
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
      // Si la IA devuelve el marcador [no_reply], ignorar la respuesta
      if (_checkAndHandleNoReply(
        outcome.result.text,
        index: existingMessageIndex,
      )) {
        return;
      }
      // Marcar como read inmediatamente al recibir la respuesta de la IA
      _setLastUserMessageStatus(
        MessageStatus.read,
        index: existingMessageIndex,
      );
      // Guardar outcome y ejecutar finalizer para aplicar el resultado tras el delay
      pendingOutcome = outcome;
      result = outcome.result;
      try {
        final outRes = outcome.result;
        isTyping = !outRes.isImage;
        isSendingImage = outRes.isImage;
        if (outcome.ttsRequested) isSendingAudio = true;
        notifyListeners();
      } catch (_) {}
      finalizeAssistantResponse();
      // Éxito de red: marcar último mensaje usuario como 'sent'
      _setLastUserMessageStatus(
        MessageStatus.sent,
        index: existingMessageIndex,
      );
    } catch (e) {
      Log.e('Error enviando mensaje', tag: 'CHAT', error: e);
      // Marcar último mensaje de usuario como failed
      // Preferir existingMessageIndex si se proporcionó
      int idx = -1;
      if (existingMessageIndex != null &&
          existingMessageIndex >= 0 &&
          existingMessageIndex < messages.length) {
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
    if (result.text.toLowerCase().contains('error al conectar con la ia') &&
        !result.isImage) {
      // Marcar mensaje como failed para permitir reintento manual
      final int idx =
          (existingMessageIndex != null &&
              existingMessageIndex >= 0 &&
              existingMessageIndex < messages.length)
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
      final idx = messages.lastIndexWhere(
        (m) => m.sender == MessageSender.user && m.isImage,
      );
      if (idx != -1) {
        final prevImage = messages[idx].image;
        if (prevImage != null) {
          messages[idx] = messages[idx].copyWith(
            image: prevImage.copyWith(prompt: result.prompt),
          );
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
    // Si la IA solicitó TTS, activamos el indicador global hasta que finalice
    if (pendingOutcome?.ttsRequested ?? false) {
      isSendingAudio = true;
    }
    Log.d(
      'isTyping=$isTyping, isSendingImage=$isSendingImage, isSendingAudio=$isSendingAudio (sendMessage)',
      tag: 'CHAT',
    );
    final delayMs = computeDelayMsFromText(result.text);
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

    // Si guardamos un pendingOutcome, el helper lo aplicará tras su propio delay.
    if (pendingOutcome != null) {
      await finalizeAssistantResponse();
      return;
    }

    if (pendingOutcome == null) {
      // Confiar en el resultado tal cual lo proporciona SendMessageUseCase.
      final assistantMessage = Message(
        text: result.text,
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        isImage: result.isImage,
        image: result.isImage
            ? AiImage(
                url: result.imagePath ?? '',
                seed: result.seed,
                prompt: result.prompt,
              )
            : null,
        status: MessageStatus.read,
      );
      // Si la IA responde con el marcador [no_reply'], no añadir ni procesar la respuesta
      // (el post-procesado - TTS / eventos - lo realiza SendMessageUseCase y se
      // aplica cuando se añadió el assistantMessage en las ramas de envío).

      // Analiza promesas IA tras cada mensaje IA
      onIaMessageSent();

      isSendingImage = false;
      isTyping = false;
      // Mantener isSendingAudio=true hasta que TTS complete y actualice el mensaje
      _imageRequestId++;

      final textResp = result.text;
      if (textResp.trim() != '' &&
          !textResp.trim().toLowerCase().contains(
            'error al conectar con la ia',
          ) &&
          !textResp.trim().toLowerCase().contains('"error"')) {
        final memManager =
            memoryManager ?? MemoryManager(profile: onboardingData);
        final memResult = await memManager.processAllSummariesAndSuperblock(
          messages: messages,
          timeline: onboardingData.timeline,
          superbloqueEntry: superbloqueEntry,
        );
        onboardingData = TimelineUpdater.applyTimelineUpdate(
          profile: onboardingData,
          timeline: memResult.timeline,
          superbloqueEntry: memResult.superbloqueEntry,
        );
        superbloqueEntry = memResult.superbloqueEntry;
      }
      // Si se agregó un placeholder de llamada entrante ya se notificó antes (evitamos doble render inmediato)
      if (assistantMessage.text.trim() != '[call][/call]') {
        notifyListeners();
      }
    }
  }

  // ================= NUEVO BLOQUE AUDIO =================
  IAudioChatService? _audioService;

  IAudioChatService get audioService =>
      _audioService ??= di.getAudioChatService(
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

    // If user selected native STT, prefer the live transcription captured
    // during listening and skip file-based transcription attempts. PrefsUtils
    // normalizes provider names (e.g., gemini -> google).
    String provider = '';
    try {
      provider = await PrefsUtils.getSelectedAudioProvider();
    } catch (_) {}

    if (provider == 'native' || provider == 'android_native') {
      // Use live transcript as the final transcription
      if (audioService.liveTranscript.trim().isNotEmpty) {
        transcript = audioService.liveTranscript.trim();
        Log.i(
          'Usando transcripción nativa en vivo como transcripción final',
          tag: 'AUDIO',
        );
      } else {
        Log.w(
          'Transcripción nativa en vivo vacía al detener; no se intentará STT de fichero',
          tag: 'AUDIO',
        );
      }
    } else {
      // Intentar transcripción con reintentos para providers cloud (Google/OpenAI)
      const maxRetries = 2;
      int attempt = 0;
      while (attempt <= maxRetries) {
        try {
          final stt = di.getSttServiceForProvider(provider);
          final result = await stt.transcribeAudio(path);
          if (result != null && result.trim().isNotEmpty) {
            transcript = result.trim();
            Log.i(
              'Transcripción exitosa en intento ${attempt + 1}',
              tag: 'AUDIO',
            );
            break;
          } else {
            Log.w(
              'Transcripción vacía en intento ${attempt + 1}',
              tag: 'AUDIO',
            );
          }
        } catch (e) {
          Log.e(
            'Error transcribiendo (intento ${attempt + 1}/$maxRetries)',
            tag: 'AUDIO',
            error: e,
          );
        }

        attempt++;
        if (attempt <= maxRetries) {
          // Backoff progresivo entre intentos
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    // Fallback: usar transcripción en vivo si la final falló o es muy corta
    if ((transcript == null ||
            transcript.trim().length < liveTranscript.trim().length) &&
        liveTranscript.isNotEmpty) {
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

    // Enviar la transcripción como texto plano (el use-case decide si requiere TTS)
    final plain = transcript.trim();
    await sendMessage(
      plain,
      model: model,
      userAudioPath: path,
      preTranscribedText: plain,
    );

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
        showAppSnackBar(
          'Error: no se pudo reproducir el audio. Recurso no encontrado.',
          isError: true,
        );
      } catch (_) {}
    }
  }

  bool isPlaying(Message msg) => audioService.isPlayingMessage(msg);
  Duration get playingPosition => audioService.currentPosition;
  Duration get playingDuration => audioService.currentDuration;

  Future<void> generateTtsForMessage(
    Message msg, {
    String voice = 'nova',
  }) async {
    // Solo procesar mensajes del asistente que NO tengan audio ya generado
    if (msg.sender != MessageSender.assistant ||
        (msg.isAudio && msg.audio?.url != null && msg.audio!.url!.isNotEmpty)) {
      return;
    }
    // Indicar que la IA está generando audio hasta que tengamos audioPath
    isSendingAudio = true;
    notifyListeners();
    // Delegar a TtsService para sintetizar y persistir el audio
    try {
      final tts =
          ttsService ?? TtsService(audioService, di.getLanguageResolver());
      final path = await tts.synthesizeAndPersist(msg.text, voice: voice);
      final idx = messages.indexOf(msg);
      if (path != null) {
        // Obtener la duración real del archivo de audio generado
        Log.d(
          '🔍 [DEBUG][TTS] generateTtsForMessage: calculating duration for file: $path',
          tag: 'TTS',
        );
        final audioDuration = await AudioDurationUtils.getAudioDuration(path);
        Log.d(
          '🔍 [DEBUG][TTS] Real duration calculated: ${audioDuration?.inMilliseconds}ms, stored in message.audioDuration',
          tag: 'TTS',
        );

        if (idx != -1) {
          // Create AiAudio object with the new data
          final audioObj = AiAudio(
            url: path,
            transcript: msg.text,
            durationMs: audioDuration?.inMilliseconds,
            isAutoTts: true,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          messages[idx] = messages[idx].copyWith(
            isAudio: true,
            audio: audioObj,
          );
          Log.d(
            '🔍 [DEBUG][TTS] Message updated - final audioDuration: ${messages[idx].audio?.duration?.inMilliseconds}ms',
            tag: 'TTS',
          );
        }
      } else {
        Log.d(
          '🔍 [DEBUG][TTS] Failed to generate TTS - no path returned',
          tag: 'TTS',
        );
        // Mark as audio requested but no path returned (error case handled below)
        if (idx != -1) {
          final audioObj = AiAudio(
            transcript: msg.text,
            isAutoTts: true,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          messages[idx] = messages[idx].copyWith(
            isAudio: true,
            audio: audioObj,
          );
        }
      }
      // Ya tenemos resultado (positivo o negativo), desactivar indicador
      isSendingAudio = false;
      if (idx != -1) notifyListeners();
    } catch (e) {
      debugPrint('[Audio][TTS] Error generating TTS: $e');
      final idx = messages.indexOf(msg);
      if (idx != -1) {
        final audioObj = AiAudio(
          transcript: msg.text,
          isAutoTts: true,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        messages[idx] = messages[idx].copyWith(isAudio: true, audio: audioObj);
      }
      isSendingAudio = false;
      if (idx != -1) notifyListeners();
    }
  }

  /// Calcula y actualiza la duración del audio grabado por el usuario
  Future<void> _calculateUserAudioDuration(Message message) async {
    if (message.audio?.url == null || message.audio!.url!.isEmpty) return;

    try {
      final audioDuration = await AudioDurationUtils.getAudioDuration(
        message.audio!.url!,
      );
      final messageIndex = messages.indexOf(message);

      if (messageIndex != -1 && audioDuration != null) {
        // Update the audio object with the new duration
        final currentAudio = messages[messageIndex].audio;
        final updatedAudio =
            currentAudio?.copyWith(durationMs: audioDuration.inMilliseconds) ??
            AiAudio(
              url: message.audio!.url,
              durationMs: audioDuration.inMilliseconds,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            );

        messages[messageIndex] = messages[messageIndex].copyWith(
          audio: updatedAudio,
        );
        notifyListeners();
        Log.d(
          'Audio: User audio duration calculated=${audioDuration.inMilliseconds}ms for ${message.audio!.url}',
          tag: 'AUDIO',
        );
      }
    } catch (e) {
      Log.w('Failed to calculate user audio duration: $e', tag: 'AUDIO');
    }
  }

  // =======================================================

  /// Aplica un SendMessageOutcome: añade el assistantMessage a la lista,
  /// dispara TTS si corresponde, actualiza onboardingData y devuelve el
  /// ChatResult para continuar el flujo.
  Future<ChatResult> _applySendOutcome(
    SendMessageOutcome outcome, {
    int? existingMessageIndex,
  }) async {
    final ChatResult chatResult = outcome.result;
    // Si la IA responde con el marcador [call][/call] debemos mostrar la UI
    // de llamada entrante en lugar de insertar un placeholder en el historial.
    final isCallPlaceholder =
        outcome.assistantMessage.text.trim() == '[call][/call]';
    if (isCallPlaceholder) {
      isCalling = true;
      pendingIncomingCallMsgIndex = null; // no placeholder stored
      Log.i(
        '[Call] IA solicita llamada entrante -> mostrando indicador isCalling=true',
        tag: 'CHAT',
      );
      // Apply profile updates if present
      if (outcome.updatedProfile != null) {
        onboardingData = outcome.updatedProfile!;
        _events
          ..clear()
          ..addAll(onboardingData.events ?? []);
      }
      notifyListeners();
    } else {
      // Decide whether to add the assistant message immediately or esperar a TTS
      final assistantMessage = outcome.assistantMessage;
      final wantsAudio = outcome.ttsRequested;

      if (wantsAudio) {
        // Mostrar indicador global de síntesis y sintetizar antes de insertar
        // Nota: SendMessageUseCase es la fuente de verdad para decidir TTS/limpieza
        isSendingAudio = true;
        notifyListeners();
        // Usar el texto provisto por outcome; no tocar etiquetas aquí.
        final String cleaned = assistantMessage.text.trim();

        try {
          // Crear mensaje como audio desde el inicio para evitar parpadeo visual
          final audioObj = AiAudio(
            transcript: cleaned,
            isAutoTts: true,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          final msgForTts = assistantMessage.copyWith(
            text: cleaned,
            isAudio: true, // Marcado como audio desde el inicio
            status: MessageStatus.read,
            audio: audioObj,
          );

          // Agregar el mensaje a la lista ANTES de generar TTS
          // (generateTtsForMessage necesita encontrar el mensaje en messages)
          messages.add(msgForTts);

          // Generar TTS y calcular duración real - esto actualizará audioPath y audioDuration
          await generateTtsForMessage(msgForTts);
        } catch (e, st) {
          Log.w('TTS failed while applying outcome: $e\n$st', tag: 'CHAT');
          // Si ya se agregó el mensaje pero falló TTS, mantenerlo como audio sin audioPath
          // La UI debería manejar esto mostrando un estado de error
          if (messages.isEmpty || messages.last.text != cleaned) {
            // Fallback: agregar como texto normal si algo salió mal
            messages.add(
              assistantMessage.copyWith(
                text: cleaned,
                status: MessageStatus.read,
              ),
            );
          }
        } finally {
          isSendingAudio = false;
          notifyListeners();
        }
      } else {
        messages.add(assistantMessage);
      }
    }
    // Actualizar onboardingData si la use-case guardó/actualizó eventos
    if (outcome.updatedProfile != null) {
      if (!isCallPlaceholder) onboardingData = outcome.updatedProfile!;
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
      final memManager =
          memoryManager ?? MemoryManager(profile: onboardingData);
      final oldLevel0Keys = (onboardingData.timeline)
          .where((t) => t.level == 0)
          .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = TimelineUpdater.applyTimelineUpdate(
        profile: onboardingData,
        timeline: memResult.timeline,
        superbloqueEntry: memResult.superbloqueEntry,
      );
      superbloqueEntry = memResult.superbloqueEntry;
      if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, memResult.timeline)) {
        Log.d(
          'Auto-backup: trigger scheduled (addAssistantMessage) — new summary block detected',
          tag: 'BACKUP_AUTO',
        );
        unawaited(_maybeTriggerAutoBackup());
      } else {
        Log.d(
          'Auto-backup: no new level-0 blocks; skip trigger (addAssistantMessage)',
          tag: 'BACKUP_AUTO',
        );
      }
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
    final MessageSender sender = incoming
        ? MessageSender.assistant
        : MessageSender.user;

    // Si hay placeholder entrante y se pasa índice, reemplazarlo conservando fecha original si existe
    if (placeholderIndex != null &&
        placeholderIndex >= 0 &&
        placeholderIndex < messages.length) {
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
    await _updateMemoryAndTimeline(
      debugContext: 'updateOrAddCallStatusMessage',
    );
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
      final memManager =
          memoryManager ?? MemoryManager(profile: onboardingData);
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = TimelineUpdater.applyTimelineUpdate(
        profile: onboardingData,
        timeline: memResult.timeline,
        superbloqueEntry: memResult.superbloqueEntry,
      );
      superbloqueEntry = memResult.superbloqueEntry;
      notifyListeners();
    } catch (e) {
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-message: $e');
    }
  }

  // ======== Soporte llamada entrante ========
  int?
  pendingIncomingCallMsgIndex; // índice del mensaje [call][/call] pendiente de contestar

  bool get hasPendingIncomingCall => pendingIncomingCallMsgIndex != null;

  void clearPendingIncomingCall() {
    pendingIncomingCallMsgIndex = null;
    isCalling = false;
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
      await _updateMemoryAndTimeline(
        debugContext: 'replaceIncomingCallPlaceholder',
      );
    }();
  }

  /// Marca una llamada entrante como rechazada antes de que hubiera conversación.
  void rejectIncomingCallPlaceholder({
    required int index,
    String text = 'Llamada rechazada',
  }) {
    if (index < 0 || index >= messages.length) return;
    final original = messages[index];
    if (!original.text.contains('[call]')) return;
    messages[index] = Message(
      text: text,
      // Mantener el sender original (assistant) para reflejar que provino de llamada IA
      sender: original.sender,
      dateTime: DateTime.now(),
      status: MessageStatus.read,
      callStatus: text.toLowerCase().contains('no contestada')
          ? CallStatus.missed
          : CallStatus.rejected,
    );
    pendingIncomingCallMsgIndex = null;
    notifyListeners();
    () async {
      try {
        final memoryService = MemorySummaryService(profile: onboardingData);
        final oldLevel0Keys = (onboardingData.timeline)
            .where((t) => t.level == 0)
            .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
            .toSet();
        final result = await memoryService.processAllSummariesAndSuperblock(
          messages: messages,
          timeline: onboardingData.timeline,
          superbloqueEntry: superbloqueEntry,
        );
        onboardingData = onboardingData.copyWith(timeline: result.timeline);
        superbloqueEntry = result.superbloqueEntry;
        if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, result.timeline)) {
          Log.d(
            'Auto-backup: trigger scheduled (rejectIncomingCallPlaceholder) — new summary block detected',
            tag: 'BACKUP_AUTO',
          );
          unawaited(_maybeTriggerAutoBackup());
        } else {
          Log.d(
            'Auto-backup: no new level-0 blocks; skip trigger (rejectIncomingCallPlaceholder)',
            tag: 'BACKUP_AUTO',
          );
        }
        notifyListeners();
      } catch (e) {
        Log.w(
          '[AI-chan][WARN] Falló actualización de memoria post-reject-call: $e',
        );
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

  /// Crea un Message con la lógica común de displayText y manejo de imagen
  Message _createMessage({
    required String text,
    String? preTranscribedText,
    String? callPrompt,
    bool isAutomaticPrompt = false,
    required DateTime dateTime,
    bool hasImage = false,
    AiImage? image,
    String? userAudioPath,
  }) {
    final String displayText;
    if (isAutomaticPrompt && callPrompt != null) {
      displayText = callPrompt;
    } else {
      displayText = preTranscribedText ?? text;
    }

    AiImage? imageForHistory;
    if (hasImage && image != null) {
      imageForHistory = AiImage(
        url: image.url,
        seed: image.seed,
        prompt: image.prompt,
      );
    }

    // Create AiAudio object if audio path provided
    AiAudio? audioObj;
    if (userAudioPath != null) {
      audioObj = AiAudio(
        url: userAudioPath,
        transcript: displayText,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    return Message(
      text: displayText,
      sender: isAutomaticPrompt ? MessageSender.system : MessageSender.user,
      dateTime: dateTime,
      isImage: hasImage,
      image: imageForHistory,
      isAudio: userAudioPath != null,
      audio: audioObj,
    );
  }

  /// Lógica común para validar y crear mensajes con imagen y prompts automáticos
  ({Message message, bool shouldAdd}) _createMessageWithValidation({
    required String text,
    String? preTranscribedText,
    String? callPrompt,
    required DateTime dateTime,
    AiImage? image,
    String? userAudioPath,
  }) {
    final bool hasImage =
        image != null &&
        (((image.base64 ?? '').isNotEmpty) || ((image.url ?? '').isNotEmpty));
    final isAutomaticPrompt =
        text.trim().isEmpty && (callPrompt != null && callPrompt.isNotEmpty);

    final msg = _createAndCheckMessage(
      text: text,
      preTranscribedText: preTranscribedText,
      callPrompt: callPrompt,
      isAutomaticPrompt: isAutomaticPrompt,
      dateTime: dateTime,
      hasImage: hasImage,
      image: image,
      userAudioPath: userAudioPath,
    );

    final shouldAdd =
        text.trim().isNotEmpty ||
        hasImage ||
        isAutomaticPrompt ||
        userAudioPath != null;
    return (message: msg, shouldAdd: shouldAdd);
  }

  Message _createAndCheckMessage({
    required String text,
    String? preTranscribedText,
    String? callPrompt,
    bool isAutomaticPrompt = false,
    required DateTime dateTime,
    bool hasImage = false,
    AiImage? image,
    String? userAudioPath,
  }) {
    final msg = _createMessage(
      text: text,
      preTranscribedText: preTranscribedText,
      callPrompt: callPrompt,
      isAutomaticPrompt: isAutomaticPrompt,
      dateTime: dateTime,
      hasImage: hasImage,
      image: image,
      userAudioPath: userAudioPath,
    );
    return msg;
  }

  Future<void> _maybeTriggerAutoBackup() async {
    try {
      await BackupAutoUploader.maybeUploadAfterSummary(
        profile: onboardingData,
        messages: messages,
        timeline: onboardingData.timeline,
        googleLinked: googleLinked,
        repository: repository,
      );
    } catch (e) {
      // swallow errors: uploader logs internally
    }
  }

  /// Lógica común de backup automático para evitar duplicación entre ramas repository/prefs
  Future<void> _executeAutoBackupLogic(String branchName) async {
    if (!googleLinked) {
      Log.d(
        'Auto-backup: skip (not linked to Google Drive)',
        tag: 'BACKUP_AUTO',
      );
      return;
    }

    try {
      // Add a small delay to ensure credentials are fully initialized
      await Future.delayed(const Duration(milliseconds: 500));

      // Double-check that we actually have valid credentials using passive method
      final storage = const FlutterSecureStorage();
      final credsStr = await storage.read(key: 'google_credentials');
      bool hasValidToken = false;
      String? storedToken;
      if (credsStr != null && credsStr.isNotEmpty) {
        final creds = jsonDecode(credsStr);
        storedToken = creds['access_token'] as String?;
        hasValidToken = storedToken != null && storedToken.isNotEmpty;
      }

      if (!hasValidToken) {
        Log.w(
          'Auto-backup: googleLinked=true but no valid token found during loadAll ($branchName). Skipping backup.',
          tag: 'BACKUP_AUTO',
        );
        return;
      }

      final lastMs = await PrefsUtils.getLastAutoBackupMs();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final twentyFourHoursMs = const Duration(hours: 24).inMilliseconds;
      final hasMessages = messages.isNotEmpty;

      // Backup logic based on requirements:
      // 1. Account linked + no backup exists → Always backup
      // 2. Account not linked → Never backup
      // 3. Account linked + backup exists + no messages (first init) → DON'T backup (preserve existing)
      // 4. Account linked + backup >24h + has messages → Backup (update with new info)

      bool shouldBackup = false;
      String reason = '';

      if (lastMs == null) {
        // Case 1: No backup exists → Always backup
        shouldBackup = true;
        reason = 'no previous backup exists';
      } else if (!hasMessages) {
        // Case 3: Has backup + no messages (first initialization) → DON'T backup
        shouldBackup = false;
        reason =
            'no messages in chat (preserving existing backup for potential restore)';
      } else if ((nowMs - lastMs) > twentyFourHoursMs) {
        // Case 4: Has backup >24h + has messages → Update backup
        shouldBackup = true;
        final hoursAgo = Duration(milliseconds: nowMs - lastMs).inHours;
        reason = 'backup is ${hoursAgo}h old and chat has messages';
      } else {
        // Recent backup + has messages → Skip to avoid spam
        shouldBackup = false;
        final hoursAgo = Duration(milliseconds: nowMs - lastMs).inHours;
        reason = 'recent backup (${hoursAgo}h ago) exists';
      }

      if (shouldBackup) {
        Log.d(
          'Auto-backup: trigger scheduled (loadAll $branchName) - $reason, messages=${messages.length}, tokenAvailable=${storedToken?.isNotEmpty ?? false}',
          tag: 'BACKUP_AUTO',
        );
        await _maybeTriggerAutoBackup();
      } else {
        Log.d(
          'Auto-backup: skip $branchName ($reason), messages=${messages.length}',
          tag: 'BACKUP_AUTO',
        );

        // Only do remote verification if we skipped backup due to recent timestamp
        // but still want to ensure remote backup actually exists
        if (lastMs != null &&
            hasMessages &&
            branchName == 'repository branch') {
          try {
            unawaited(() async {
              try {
                final svc = GoogleBackupService(accessToken: storedToken);
                final files = await svc.listBackups();
                if (files.isEmpty) {
                  Log.d(
                    'Auto-backup: no remote backups found despite recent local ts; forcing upload',
                    tag: 'BACKUP_AUTO',
                  );
                  await _maybeTriggerAutoBackup();
                } else {
                  Log.d(
                    'Auto-backup: remote backup present; skipping upload',
                    tag: 'BACKUP_AUTO',
                  );
                }
              } catch (e) {
                Log.w(
                  'Auto-backup: remote verification failed: $e',
                  tag: 'BACKUP_AUTO',
                );
              }
            }());
          } catch (_) {}
        }
      }
    } catch (e) {
      Log.w('Auto-backup: $branchName failed: $e', tag: 'BACKUP_AUTO');
    }
  }

  /// Helper común para actualizar memoria y timeline tras mensajes IA
  Future<void> _updateMemoryAndTimeline({String debugContext = ''}) async {
    try {
      final memManager =
          memoryManager ?? MemoryManager(profile: onboardingData);
      final oldLevel0Keys = (onboardingData.timeline)
          .where((t) => t.level == 0)
          .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: messages,
        timeline: onboardingData.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      onboardingData = TimelineUpdater.applyTimelineUpdate(
        profile: onboardingData,
        timeline: memResult.timeline,
        superbloqueEntry: memResult.superbloqueEntry,
      );
      superbloqueEntry = memResult.superbloqueEntry;
      if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, memResult.timeline)) {
        final context = debugContext.isNotEmpty ? ' ($debugContext)' : '';
        Log.d(
          'Auto-backup: trigger scheduled$context — new summary block detected',
          tag: 'BACKUP_AUTO',
        );
        unawaited(_maybeTriggerAutoBackup());
      } else {
        final context = debugContext.isNotEmpty ? ' ($debugContext)' : '';
        Log.d(
          'Auto-backup: no new level-0 blocks; skip trigger$context',
          tag: 'BACKUP_AUTO',
        );
      }
      notifyListeners();
    } catch (e) {
      Log.w(
        '[AI-chan][WARN] Falló actualización de memoria post-$debugContext: $e',
      );
    }
  }

  /// que no estaban en el conjunto de claves precomputadas `oldKeys`.
  bool _hasNewLevel0EntriesFromKeys(
    Set<String> oldKeys,
    List<TimelineEntry> newTimeline,
  ) {
    try {
      for (final t in newTimeline.where((t) => t.level == 0)) {
        final key = '${t.startDate ?? ''}|${t.endDate ?? ''}';
        if (!oldKeys.contains(key)) return true;
      }
    } catch (_) {}
    return false;
  }

  // Generador de apariencia desacoplado
  final IAAppearanceGenerator iaAppearanceGenerator = IAAppearanceGenerator();

  /// Ejecuta un único intento del flujo: generar avatar a partir de la apariencia existente -> persistir
  /// Si [replace] es false, añade el avatar al historial y crea un mensaje system notificándolo.
  /// No realiza reintentos adicionales: los generadores internos ya aplican retry.
  Future<void> createAvatarFromAppearance({
    required bool replace,
    bool showErrorDialog = true,
  }) async {
    // This method only generates the avatar from an existing appearance.
    // Appearance generation must be done separately via IAAppearanceGenerator.
    final bio = onboardingData;
    if (bio.appearance.isEmpty) {
      throw Exception(
        'Falta la apariencia en el perfil. Genera la apariencia primero.',
      );
    }

    // La lógica de aplicación/persistencia se implementa en el método de clase
    // `_applyAvatarAndPersist` para evitar warnings de identificadores locales
    // y mejorar testabilidad.

    try {
      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
        bio,
        appendAvatar: !replace,
      );
      await _applyAvatarAndPersist(avatar, replace: replace);
    } catch (e) {
      // Si la generación con los intentos internos falló, preguntar al usuario si quiere reintentar
      if (showErrorDialog) {
        final choice = await showRegenerateAppearanceErrorDialog(e);
        if (choice == 'retry') {
          try {
            final avatar2 = await IAAvatarGenerator()
                .generateAvatarFromAppearance(bio, appendAvatar: !replace);
            await _applyAvatarAndPersist(avatar2, replace: replace);
          } catch (e2) {
            Log.w(
              'Reintento manual de generación de avatar falló: $e2',
              tag: 'CHAT',
            );
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
  Future<void> _applyAvatarAndPersist(
    AiImage avatar, {
    required bool replace,
  }) async {
    // Delegate to centralized util that persists and notifies.
    await addAvatarAndPersist(this, avatar, replace: replace);
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
          Log.w(
            'Reintento manual de generar apariencia falló: $e2',
            tag: 'CHAT',
          );
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  // Helper privado que realiza un único intento de generar la apariencia,
  // persistirla y luego generar el avatar reemplazando los existentes.
  Future<void> _doGenerateAppearanceAndReplaceAvatar({
    bool persist = true,
  }) async {
    final appearanceMap = await iaAppearanceGenerator
        .generateAppearanceFromBiography(onboardingData);
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
    try {
      if (_selectedModel != null) {
        await PrefsUtils.setSelectedModel(_selectedModel!);
      } else {
        // store empty to indicate unset
        await PrefsUtils.setSelectedModel('');
      }
    } catch (_) {}
  }

  Future<void> loadSelectedModel() async {
    try {
      _selectedModel = await PrefsUtils.getSelectedModel();
    } catch (_) {
      _selectedModel = null;
    }
    notifyListeners();
  }

  // _extractWaitSeconds eliminado (reintentos ahora están en SendMessageUseCase)

  /// Limpia el texto para mostrarlo correctamente en el chat (quita escapes JSON)
  String cleanText(String text) {
    return text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }

  bool isSummarizing = false;
  bool isTyping = false;
  bool isSendingImage = false;

  /// Indicador para llamadas entrantes: si true la UI debe mostrar el flujo
  /// de llamada entrante sin necesidad de añadir un mensaje placeholder.
  bool isCalling = false;
  bool isSendingAudio = false;
  bool isUploadingUserAudio = false;
  List<Message> messages = [];
  late AiChanProfile onboardingData;

  // Google account state propagated from the Drive linking flow.
  String? googleEmail;
  String? googleAvatarUrl;
  String? googleName;
  bool googleLinked = false;

  // Export/import moved to utilities. Methods removed to decouple BackupService
  // from provider state; callers must use BackupUtils and ChatJsonUtils.

  Future<void> saveAll() async {
    final exported = ImportedChat(
      profile: onboardingData,
      messages: messages,
      events: _events,
    );
    // Prefer repository if provided
    if (repository != null) {
      try {
        await repository!.saveAll(exported.toJson());
        return;
      } catch (e) {
        Log.w(
          'IChatRepository.saveAll failed, falling back to StorageUtils: $e',
          tag: 'PERSIST',
        );
      }
    }
    // Fallback: legacy StorageUtils via ProviderPersistUtils helper
    try {
      await ProviderPersistUtils.saveImportedChat(
        exported,
        repository: repository,
      );
    } catch (e) {
      Log.w('ProviderPersistUtils.saveImportedChat failed: $e', tag: 'PERSIST');
    }
  }

  /// Aplica un `ImportedChat` ya parseado al provider, persiste y restaura
  /// cualquier estado dependiente (events, promesas) y notifica listeners.
  Future<void> applyImportedChat(ImportedChat imported) async {
    onboardingData = imported.profile;
    messages = imported.messages.cast<Message>();
    _events.clear();
    if (imported.events.isNotEmpty) _events.addAll(imported.events);
    // Persistir usando la ruta configurada
    await saveAll();
    // Restaurar eventos en el servicio de promesas
    try {
      _promiseService.restoreFromEvents();
    } catch (_) {}
    notifyListeners();
  }

  /// Update the global Google account info and persist to SharedPreferences.
  /// [triggerAutoBackup]: Si true, puede disparar backup automático cuando linked=true.
  /// Debe ser false cuando se llama desde verificaciones de estado en diálogos.
  Future<void> updateGoogleAccountInfo({
    String? email,
    String? avatarUrl,
    String? name,
    bool linked = true,
    bool triggerAutoBackup = false,
  }) async {
    googleEmail = email;
    googleAvatarUrl = avatarUrl;
    googleName = name;
    googleLinked = linked;
    try {
      if (kDebugMode) {
        debugPrint(
          'updateGoogleAccountInfo called: email=$email name=$name avatar=$avatarUrl linked=$linked triggerAutoBackup=$triggerAutoBackup',
        );
      }
    } catch (_) {}
    try {
      await PrefsUtils.setGoogleAccountInfo(
        email: email,
        avatar: avatarUrl,
        name: name,
        linked: linked,
      );
    } catch (_) {}
    notifyListeners();
    // Solo disparar backup automático si se autoriza explícitamente (ej: desde loadAll, no desde diálogos)
    if (linked && triggerAutoBackup) {
      try {
        unawaited(() async {
          try {
            // Add a small delay to ensure credentials are fully saved and available
            await Future.delayed(const Duration(seconds: 1));

            // Verify that credentials are actually available using passive method
            final storage = const FlutterSecureStorage();
            final credsStr = await storage.read(key: 'google_credentials');
            bool hasValidToken = false;
            if (credsStr != null && credsStr.isNotEmpty) {
              final creds = jsonDecode(credsStr);
              final accessToken = creds['access_token'] as String?;
              hasValidToken = accessToken != null && accessToken.isNotEmpty;
            }

            if (!hasValidToken) {
              Log.w(
                'Auto-backup: account linked but no valid token available yet. Will retry on next app load.',
                tag: 'BACKUP_AUTO',
              );
              return;
            }

            final lastMs = await PrefsUtils.getLastAutoBackupMs();
            final nowMs = DateTime.now().millisecondsSinceEpoch;

            // When account is JUST linked (this method called), be more aggressive about backing up
            // Check if we should trigger backup when account linking happens:
            // 1. Never backed up before (lastMs == null), OR
            // 2. Last backup is older than 30 minutes (account re-link scenario)
            final thirtyMinutesMs = const Duration(minutes: 30).inMilliseconds;
            final shouldBackupOnLink =
                lastMs == null || (nowMs - lastMs) > thirtyMinutesMs;

            if (shouldBackupOnLink) {
              final timeSince = lastMs != null
                  ? Duration(milliseconds: nowMs - lastMs)
                  : null;
              Log.d(
                'Auto-backup: trigger scheduled (updateGoogleAccountInfo) - reason: ${lastMs == null ? 'never backed up' : 'account re-linked after ${timeSince!.inMinutes}m'} tokenAvailable=$hasValidToken',
                tag: 'BACKUP_AUTO',
              );
              await _maybeTriggerAutoBackup();
            } else {
              final timeSince = Duration(milliseconds: nowMs - lastMs);
              Log.d(
                'Auto-backup: recent backup (${timeSince.inMinutes}m ago) + fresh link, skipping to avoid spam',
                tag: 'BACKUP_AUTO',
              );
            }
          } catch (e) {
            Log.w(
              'Auto-backup: updateGoogleAccountInfo branch failed: $e',
              tag: 'BACKUP_AUTO',
            );
          }
        }());
      } catch (_) {}
    } else if (linked && !triggerAutoBackup) {
      Log.d(
        'Auto-backup: skip trigger (updateGoogleAccountInfo called from dialog verification)',
        tag: 'BACKUP_AUTO',
      );
    }
  }

  /// Debug method to diagnose Google authentication state
  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    final diagnosis = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'chatProviderState': {
        'googleLinked': googleLinked,
        'googleEmail': googleEmail,
        'googleName': googleName,
        'googleAvatarUrl': googleAvatarUrl,
      },
    };

    try {
      // Check what's stored in prefs
      final prefsInfo = await PrefsUtils.getGoogleAccountInfo();
      diagnosis['prefsState'] = prefsInfo;
    } catch (e) {
      diagnosis['prefsError'] = e.toString();
    }

    try {
      // Check actual token availability using passive method
      final storage = const FlutterSecureStorage();
      final credsStr = await storage.read(key: 'google_credentials');
      bool hasValidToken = false;
      int tokenLength = 0;
      if (credsStr != null && credsStr.isNotEmpty) {
        final creds = jsonDecode(credsStr);
        final accessToken = creds['access_token'] as String?;
        hasValidToken = accessToken != null && accessToken.isNotEmpty;
        tokenLength = accessToken?.length ?? 0;
      }

      diagnosis['hasValidToken'] = hasValidToken;
      diagnosis['tokenLength'] = tokenLength;
    } catch (e) {
      diagnosis['tokenCheckError'] = e.toString();
    }

    try {
      // Get comprehensive Google Backup Service diagnosis
      final serviceStatus =
          await GoogleBackupService.diagnoseAndroidSessionIssues();
      diagnosis['serviceStatus'] = serviceStatus;
    } catch (e) {
      diagnosis['serviceStatusError'] = e.toString();
    }

    try {
      // Get circuit breaker status
      final cbStatus = GoogleBackupService.getCircuitBreakerStatus();
      diagnosis['circuitBreakerStatus'] = cbStatus;
    } catch (e) {
      diagnosis['circuitBreakerError'] = e.toString();
    }

    Log.i(
      'Google authentication diagnosis: $diagnosis',
      tag: 'GoogleDiagnostic',
    );
    return diagnosis;
  }

  /// Clear stored Google account info both in memory and persisted prefs.
  Future<void> clearGoogleAccountInfo() async {
    googleEmail = null;
    googleAvatarUrl = null;
    googleName = null;
    googleLinked = false;
    try {
      await PrefsUtils.clearGoogleAccountInfo();
    } catch (_) {}
    notifyListeners();
  }

  /// Muestra un diálogo de error centrado para errores de regeneración
  /// y devuelve la elección del usuario: 'retry' o 'cancel' o null.
  Future<String?> showRegenerateAppearanceErrorDialog(Object error) async {
    try {
      return await showAppDialog<String>(
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            'Error generando apariencia/avatar',
            style: TextStyle(color: AppColors.secondary),
          ),
          content: SingleChildScrollView(
            child: Text(
              error.toString(),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text(
                'Cerrar',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('retry'),
              child: const Text(
                'Reintentar',
                style: TextStyle(color: AppColors.secondary),
              ),
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
            // Si cargamos desde repository, asegurarnos de forzar copia automática
            // en el primer arranque si procede (misma lógica que más abajo).
            try {
              () async {
                try {
                  final g = await PrefsUtils.getGoogleAccountInfo();
                  googleEmail = g['email'] as String?;
                  googleAvatarUrl = g['avatar'] as String?;
                  googleName = g['name'] as String?;

                  // Only mark as linked if we have actual valid tokens
                  final prefsLinked = g['linked'] as bool? ?? false;
                  if (prefsLinked) {
                    try {
                      final tokenLoader = GoogleBackupService(
                        accessToken: null,
                      );
                      final storedToken = await tokenLoader
                          .loadStoredAccessToken();
                      googleLinked =
                          storedToken != null && storedToken.isNotEmpty;

                      if (!googleLinked && prefsLinked) {
                        Log.w(
                          'Google account marked as linked in prefs but no valid tokens found (repository branch). Clearing linked status.',
                          tag: 'GoogleBackup',
                        );
                        // Clear the inconsistent state in prefs
                        await PrefsUtils.setGoogleAccountInfo(
                          email: googleEmail,
                          avatar: googleAvatarUrl,
                          name: googleName,
                          linked: false,
                        );
                      }
                    } catch (e) {
                      Log.w(
                        'Failed to verify Google tokens during repository loadAll: $e. Marking as not linked.',
                        tag: 'GoogleBackup',
                      );
                      googleLinked = false;
                    }
                  } else {
                    googleLinked = false;
                  }
                } catch (_) {}
                if (googleLinked) {
                  await _executeAutoBackupLogic('repository branch');
                }
              }();
            } catch (_) {}
            return;
          } catch (e) {
            Log.w(
              'Failed to parse repository.loadAll result: $e',
              tag: 'PERSIST',
            );
          }
        }
      } catch (e) {
        Log.w(
          'IChatRepository.loadAll failed, falling back to SharedPreferences: $e',
          tag: 'PERSIST',
        );
      }
    }

    // Fallback legacy loading via PrefsUtils
    // Restaurar biografía
    final bioString = await PrefsUtils.getOnboardingData();
    if (bioString != null) {
      onboardingData = AiChanProfile.fromJson(jsonDecode(bioString));
    }
    // Restaurar mensajes
    final jsonString = await PrefsUtils.getChatHistory();
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
    final eventsString = await PrefsUtils.getEvents();
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
      final sevenDays = const Duration(days: 7).inMilliseconds;
      final lastAvatarCreatedMs = onboardingData.avatar?.createdAtMs;
      final seed = onboardingData.avatar?.seed;
      if (seed != null &&
          seed.isNotEmpty &&
          lastAvatarCreatedMs != null &&
          (nowMs - lastAvatarCreatedMs) > sevenDays) {
        // Ejecutar generación asíncrona sin bloquear el loadAll() final
        () async {
          try {
            final appearanceMap = await iaAppearanceGenerator
                .generateAppearanceFromBiography(onboardingData);
            // Generate a new avatar using the same seed (append), but for weekly regen we want
            // to make it the current avatar; we append then set avatars to the new one.
            // Generate using same seed but replace the current avatars (weekly regeneration)
            final updatedProfile = onboardingData.copyWith(
              appearance: appearanceMap,
            );
            final avatar = await IAAvatarGenerator()
                .generateAvatarFromAppearance(
                  updatedProfile,
                  appendAvatar: true,
                );
            await addAvatarAndPersist(this, avatar, replace: true);
            // Insertar un mensaje system para que la IA tenga consciencia de la actualización
            try {
              final sysMsg = Message(
                text:
                    'Tu avatar se ha actualizado. Usa la nueva imagen como referencia en futuras respuestas.',
                sender: MessageSender.system,
                dateTime: DateTime.now(),
                status: MessageStatus.read,
              );
              messages.add(sysMsg);
            } catch (_) {}
            await saveAll();
            notifyListeners();
          } catch (e) {
            Log.w(
              'Error generando avatar semanal en background: $e',
              tag: 'CHAT',
            );
            // Mostrar diálogo de error centralizado y permitir reintento manual
            try {
              final choice = await showRegenerateAppearanceErrorDialog(e);
              if (choice == 'retry') {
                try {
                  final appearanceMap2 = await iaAppearanceGenerator
                      .generateAppearanceFromBiography(onboardingData);
                  final updatedProfile2 = onboardingData.copyWith(
                    appearance: appearanceMap2,
                  );
                  final avatar2 = await IAAvatarGenerator()
                      .generateAvatarFromAppearance(
                        updatedProfile2,
                        appendAvatar: true,
                      );
                  await addAvatarAndPersist(this, avatar2, replace: true);
                  try {
                    final sysMsg2 = Message(
                      text:
                          'Tu avatar se ha actualizado. Usa la nueva imagen como referencia en futuras respuestas.',
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
    // Restore persisted Google account display info so menus reflect linked session immediately
    try {
      final g = await PrefsUtils.getGoogleAccountInfo();
      googleEmail = g['email'] as String?;
      googleAvatarUrl = g['avatar'] as String?;
      googleName = g['name'] as String?;

      // Only mark as linked if we have actual valid tokens
      final prefsLinked = g['linked'] as bool? ?? false;
      if (prefsLinked) {
        // Verify that we actually have valid tokens before marking as linked
        // Use passive check that doesn't trigger OAuth flows
        try {
          // Read stored credentials directly without triggering OAuth
          final storage = const FlutterSecureStorage();
          final credsStr = await storage.read(key: 'google_credentials');
          bool hasValidToken = false;
          if (credsStr != null && credsStr.isNotEmpty) {
            final creds = jsonDecode(credsStr);
            final accessToken = creds['access_token'] as String?;
            hasValidToken = accessToken != null && accessToken.isNotEmpty;
          }

          googleLinked = hasValidToken;

          if (!googleLinked && prefsLinked) {
            Log.w(
              'Google account marked as linked in prefs but no valid tokens found. Clearing linked status.',
              tag: 'GoogleBackup',
            );
            // Clear the inconsistent state in prefs
            await PrefsUtils.setGoogleAccountInfo(
              email: googleEmail,
              avatar: googleAvatarUrl,
              name: googleName,
              linked: false,
            );
          }
        } catch (e) {
          Log.w(
            'Failed to verify Google tokens during loadAll: $e. Marking as not linked.',
            tag: 'GoogleBackup',
          );
          googleLinked = false;
        }
      } else {
        googleLinked = false;
      }
    } catch (_) {}
    // Diagnostic logging: record state relevant for initial automatic backup
    try {
      final lastMs = await PrefsUtils.getLastAutoBackupMs();
      Log.d(
        'Auto-backup diagnostic: googleLinked=$googleLinked messages=${messages.length} lastAutoBackupMs=$lastMs',
        tag: 'BACKUP_AUTO',
      );
    } catch (_) {}
    notifyListeners();
    // If linked to Google Drive, force a backup if last successful auto-backup
    // is older than 24h. Fire-and-forget to avoid blocking load.
    try {
      if (googleLinked) {
        () async {
          await _executeAutoBackupLogic('prefs branch');
        }();
      } else {
        Log.d(
          'Auto-backup: skip (not linked to Google Drive)',
          tag: 'BACKUP_AUTO',
        );
      }
    } catch (_) {}
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
        Log.w(
          'IChatRepository.clearAll failed, falling back: $e',
          tag: 'PERSIST',
        );
        try {
          await PrefsUtils.removeChatHistory();
          await PrefsUtils.removeOnboardingData();
        } catch (_) {}
      }
    } else {
      try {
        await PrefsUtils.removeChatHistory();
        await PrefsUtils.removeOnboardingData();
      } catch (_) {}
    }
    messages.clear();
    // Limpiar cola de envío diferido
    _clearQueuedState();
    Log.d('[AI-chan] clearAll completado, mensajes: ${messages.length}');
    notifyListeners();
  }

  /// Limpia el estado interno de la cola de envío diferido.
  void _clearQueuedState() {
    _queueManager?.clear();
  }

  /// Fuerza el procesamiento inmediato de la cola (útil para un botón "Enviar ahora").
  Future<void> flushQueuedMessages() async {
    // Force immediate flush via MessageQueueManager
    _queueManager?.flushNow();
  }

  @override
  void notifyListeners() {
    // Debounce persistence to avoid excessive disk writes when many state
    // updates happen quickly (e.g., during message streaming).
    saveAllEvents();
    // Use DebouncedPersistenceMixin helper
    triggerDebouncedSave();
    super.notifyListeners();
  }

  Future<void> saveAllEvents() async {
    final eventsJson = jsonEncode(_events.map((e) => e.toJson()).toList());
    try {
      await PrefsUtils.setEvents(eventsJson);
    } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      audioService.dispose();
    } catch (_) {}
    disposeDebouncedPersistence();
    _queueManager?.dispose();
    try {
      _periodicScheduler.stop();
    } catch (_) {}
    super.dispose();
  }

  /// Reintenta enviar el último mensaje marcado como failed.
  /// Devuelve true si arrancó un reintento, false si no había mensajes failed.
  Future<bool> retryLastFailedMessage({void Function(String)? onError}) async {
    final idx = messages.lastIndexWhere(
      (m) => m.sender == MessageSender.user && m.status == MessageStatus.failed,
    );
    if (idx == -1) return false;
    final msg = messages[idx];
    // Reintentar reusando la lógica de sendMessage, pasando existingMessageIndex
    await sendMessage(
      msg.text,
      image: msg.image,
      model: _selectedModel,
      onError: onError,
      existingMessageIndex: idx,
    );
    return true;
  }
}

// (Legacy IaPromiseService eliminado; PromiseService unifica la lógica de promesas)
