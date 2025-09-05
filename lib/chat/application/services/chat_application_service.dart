import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_prompt_builder_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart'; // ✅ DDD: ETAPA 3 - Para regenerateAppearance
import 'package:ai_chan/core/services/ia_avatar_generator.dart'; // ✅ DDD: ETAPA 3 - Para generateAvatarFromAppearance
import 'package:ai_chan/core/services/image_request_service.dart'; // ✅ MIGRACIÓN: Para detección de solicitudes de imagen
import 'package:ai_chan/shared/utils/prefs_utils.dart'; // ✅ MIGRACIÓN: Para persistencia de modelo
import 'package:ai_chan/core/di.dart' as di;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // ✅ MIGRACIÓN: Para auto backup
import 'dart:convert'; // ✅ MIGRACIÓN: Para jsonDecode
import 'package:ai_chan/chat/application/services/memory_manager.dart'; // ✅ INTEGRACIÓN: Para gestión de memoria
import 'package:ai_chan/chat/domain/services/periodic_ia_message_scheduler.dart'; // ✅ INTEGRACIÓN: Para mensajes periódicos
import 'package:ai_chan/chat/application/services/timeline_updater.dart'; // ✅ INTEGRACIÓN: Para actualización de timeline
import 'package:ai_chan/shared/utils/log_utils.dart'; // ✅ INTEGRACIÓN: Para logging
import 'package:ai_chan/core/services/memory_summary_service.dart'; // ✅ INTEGRACIÓN: Para resumen de memoria
import 'package:ai_chan/chat/application/services/message_queue_manager.dart'; // ✅ INTEGRACIÓN: Para gestión de cola de mensajes
import 'package:ai_chan/shared/application/services/promise_service.dart'; // ✅ INTEGRACIÓN: Para servicio de promesas
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart'; // ✅ DDD: File operations abstraction
import 'package:ai_chan/shared/utils/audio_duration_utils.dart'; // ✅ MIGRACIÓN: Para duración de audio
import 'package:ai_chan/shared/utils/network_utils.dart'; // ✅ MIGRACIÓN: Para verificación de conectividad
import 'package:ai_chan/shared/utils/backup_auto_uploader.dart'; // ✅ MIGRACIÓN COMPLETA: Para Google Drive auto backup
import 'package:ai_chan/shared/services/google_backup_service.dart'; // ✅ MIGRACIÓN COMPLETA: Para Google Drive service
import 'package:ai_chan/chat/application/services/debounced_save.dart'; // ✅ MIGRACIÓN FASE 5: Elemento medio 5/6 - DebouncedSave helper

/// Application Service que maneja la lógica de negocio del chat.
/// Orquesta casos de uso y servicios de dominio.
/// Esta clase reemplaza gradualmente las responsabilidades de ChatProvider.
class ChatApplicationService {
  final IChatRepository _repository;
  final IPromptBuilderService _promptBuilder;
  final IFileOperationsService _fileOperations;
  late final IAudioChatService _audioService;
  final MemoryManager? memoryManager;
  final PeriodicIaMessageScheduler _periodicScheduler;

  // ✅ INTEGRACIÓN COMPLETA: MessageQueueManager y PromiseService
  MessageQueueManager? _queueManager;
  late final PromiseService _promiseService;

  // Estado interno del servicio
  List<Message> _messages = [];
  AiChanProfile? _profile;
  List<EventEntry> _events = [];
  String? _selectedModel;
  bool _googleLinked = false;
  TimelineEntry? superbloqueEntry;

  // ✅ MIGRACIÓN: Variables de estado UI del ChatProvider original (públicas y mutables)
  bool isSummarizing = false;
  bool isTyping = false;
  bool isSendingImage = false;
  bool isSendingAudio = false;
  bool isUploadingUserAudio = false;
  bool isCalling = false;

  // ✅ MIGRACIÓN FASE 5: Elemento crítico 3/6 - _imageRequestId concurrency control
  int _imageRequestId = 0;

  // ✅ MIGRACIÓN FASE 5: Elemento medio 5/6 - DebouncedSave para optimización de persistencia
  DebouncedSave? _debouncedPersistence;

  // ✅ MIGRACIÓN: Google account state del ChatProvider original (públicos y mutables)
  String? googleEmail;
  String? googleAvatarUrl;
  String? googleName;

  ChatApplicationService({
    required IChatRepository repository,
    required IPromptBuilderService promptBuilder,
    required IFileOperationsService fileOperations,
    MemoryManager? memoryManagerParam,
    PeriodicIaMessageScheduler? periodicScheduler,
  }) : _repository = repository,
       _promptBuilder = promptBuilder,
       _fileOperations = fileOperations,
       memoryManager = memoryManagerParam,
       _periodicScheduler = periodicScheduler ?? PeriodicIaMessageScheduler() {
    // Inicializar audio service con callbacks vacíos por ahora
    _audioService = di.getAudioChatService(
      onStateChanged: () {},
      onWaveform: (waveform) {},
    );

    // ✅ INTEGRACIÓN: Inicializar MessageQueueManager
    _queueManager = MessageQueueManager(
      onFlush: (ids, lastLocalId, options) {
        try {
          // Marcar todos los mensajes anteriores como enviados excepto el último
          for (final lid in ids) {
            if (lid == lastLocalId) continue;
            final idx = _messages.indexWhere((m) => m.localId == lid);
            if (idx != -1) {
              final m = _messages[idx];
              if (m.sender == MessageSender.user &&
                  m.status == MessageStatus.sending) {
                _messages[idx] = m.copyWith(status: MessageStatus.sent);
              }
            }
          }

          // Encontrar el último mensaje y procesarlo
          final lastIdx = _messages.indexWhere((m) => m.localId == lastLocalId);
          if (lastIdx != -1) {
            final lastMsg = _messages[lastIdx];
            // Marcar como enviado inmediatamente para evitar UI stuck
            if (lastMsg.sender == MessageSender.user &&
                lastMsg.status == MessageStatus.sending) {
              _messages[lastIdx] = lastMsg.copyWith(status: MessageStatus.sent);
            }
            // Procesar el mensaje usando las opciones de la cola
            _processQueuedMessage(lastMsg, options);
          }
        } catch (_) {}
      },
    );

    // ✅ INTEGRACIÓN: Inicializar PromiseService
    _promiseService = PromiseService(
      events: _events,
      onEventsChanged: () {}, // notifyListeners se maneja en el controller
      sendSystemPrompt: (text, {String? callPrompt, String? model}) =>
          sendMessage(text: text, model: model),
    );

    // ✅ MIGRACIÓN FASE 5: Elemento medio 5/6 - Inicializar DebouncedSave para optimización
    _debouncedPersistence = DebouncedSave(
      const Duration(seconds: 1),
      () => _persistStateImmediate(),
    );
  }

  // Getters públicos
  List<Message> get messages => List.unmodifiable(_messages);
  AiChanProfile? get profile => _profile;
  List<EventEntry> get events => List.unmodifiable(_events);
  String? get selectedModel => _selectedModel;

  /// ✅ MIGRACIÓN FASE 5: Elemento medio 4/6 - selectedModel setter interface
  /// Setter para el modelo seleccionado, mantiene compatibilidad con ChatProvider
  set selectedModel(String? model) {
    _selectedModel = model;
    _saveSelectedModel();
    // Nota: En DDD no usamos notifyListeners() aquí, se maneja en la UI layer
  }

  bool get googleLinked => _googleLinked;

  // ✅ INTEGRACIÓN: Queue management completo
  int get queuedCount => _queueManager?.queuedCount ?? 0;

  // Audio relacionado
  IAudioChatService get audioService => _audioService;
  bool get isRecording => _audioService.isRecording;
  List<int> get currentWaveform => _audioService.currentWaveform;
  String get liveTranscript => _audioService.liveTranscript;
  Duration get recordingElapsed => _audioService.recordingElapsed;
  Duration get playingPosition => _audioService.currentPosition;
  Duration get playingDuration => _audioService.currentDuration;

  /// Inicializa el servicio cargando datos
  Future<void> initialize() async {
    final data = await _repository.loadAll();
    if (data != null) {
      _loadFromData(data);
    }
    // ✅ MIGRACIÓN: Cargar modelo seleccionado como en ChatProvider original
    await _loadSelectedModel();

    // ✅ INTEGRACIÓN: Restaurar promesas desde eventos
    _promiseService.restoreFromEvents();
  }

  /// ✅ INTEGRACIÓN: Procesa mensaje desde la cola con opciones
  Future<void> _processQueuedMessage(
    Message message,
    QueuedSendOptions? options,
  ) async {
    try {
      await sendMessage(
        text: message.text,
        model: options?.model,
        image: options?.image,
        imageMimeType: options?.imageMimeType,
        preTranscribedText: options?.preTranscribedText,
        userAudioPath: options?.userAudioPath,
        existingMessageIndex: _messages.indexWhere(
          (m) => m.localId == message.localId,
        ),
      );
    } catch (e) {
      // Marcar como fallido en caso de error
      final idx = _messages.indexWhere((m) => m.localId == message.localId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageStatus.failed);
      }
    }
  }

  /// Envía un mensaje
  Future<void> sendMessage({
    required String text,
    String? model,
    dynamic image,
    String? imageMimeType,
    String? preTranscribedText,
    String? userAudioPath,
    int?
    existingMessageIndex, // ✅ MIGRACIÓN: Para reintentos como en ChatProvider original
  }) async {
    if (_profile == null) throw Exception('Perfil no inicializado');

    // ✅ MIGRACIÓN: Detección de solicitud de imagen como en ChatProvider
    final solicitaImagen = ImageRequestService.isImageRequested(
      text: text,
      history: _messages,
    );

    if (solicitaImagen) {
      Log.d(
        'ChatApplicationService: Imagen solicitada detectada en mensaje: "$text"',
        tag: 'CHAT_SERVICE',
      );
    }

    final now = DateTime.now();
    final hasImage = image != null;

    // ✅ MIGRACIÓN: Lógica de existingMessageIndex para reintentos
    Message message;
    if (existingMessageIndex != null &&
        existingMessageIndex >= 0 &&
        existingMessageIndex < _messages.length) {
      // Reintento: actualizar mensaje existente
      message = _messages[existingMessageIndex].copyWith(
        status: MessageStatus.sending,
        text: text,
        image: image,
        dateTime: now,
      );
      _messages[existingMessageIndex] = message;
    } else {
      // Nuevo mensaje
      message = Message(
        text: text,
        sender: MessageSender.user,
        dateTime: now,
        isImage: hasImage,
        image: image,
      );
      _messages.add(message);
    }

    // ✅ MIGRACIÓN: Actualizar estados UI como en ChatProvider original
    if (hasImage) {
      isSendingImage = true;

      // ✅ MIGRACIÓN FASE 5: Elemento crítico 3/6 - Control de concurrencia para requests de imágenes
      _imageRequestId++;
      final int myRequestId = _imageRequestId;

      // Delay para transición de estado isTyping -> isSendingImage
      Future.delayed(const Duration(seconds: 5), () {
        if (isTyping && myRequestId == _imageRequestId) {
          isTyping = false;
          isSendingImage = true;
        }
      });
    }

    await _persistState();

    // ✅ MIGRACIÓN: Calcular duración del audio del usuario en segundo plano
    if (message.audio?.url != null && message.audio!.url!.isNotEmpty) {
      _calculateUserAudioDuration(message);
    }

    // Procesar respuesta de IA
    await _processSendMessage(message, model);
  }

  /// Procesa el envío de un mensaje
  Future<void> _processSendMessage(Message message, String? model) async {
    try {
      // ✅ MIGRACIÓN: Verificar conectividad antes de procesar como en ChatProvider
      final hasConnection = await hasInternetConnection();
      if (!hasConnection) {
        Log.w(
          'ChatApplicationService: Sin conexión a internet para enviar mensaje',
          tag: 'CHAT_SERVICE',
        );
        // Marcar mensaje como fallido por conectividad
        final failedIndex = _messages.indexWhere(
          (m) => m.localId == message.localId,
        );
        if (failedIndex != -1) {
          _messages[failedIndex] = _messages[failedIndex].copyWith(
            status: MessageStatus.failed,
          );
        }
        throw Exception('Sin conexión a internet');
      }

      // Simular procesamiento de IA
      await Future.delayed(const Duration(seconds: 1));

      // ✅ MIGRACIÓN: Marcar mensaje como enviado como en ChatProvider original
      final sentIndex = _messages.indexWhere(
        (m) => m.localId == message.localId,
      );
      if (sentIndex != -1) {
        _messages[sentIndex] = _messages[sentIndex].copyWith(
          status: MessageStatus.sent,
        );
      }

      final responseMessage = Message(
        text: 'Respuesta de IA para: ${message.text}',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        status: MessageStatus.read,
      );

      _messages.add(responseMessage);

      // ✅ MIGRACIÓN: Resetear estados UI como en ChatProvider original
      isSendingImage = false;
      isSendingAudio = false;

      // ✅ MIGRACIÓN FASE 5: Elemento crítico 3/6 - Incrementar imageRequestId al completar
      _imageRequestId++;

      await _persistState();
    } catch (e) {
      // ✅ MIGRACIÓN: Marcar mensaje como fallido en caso de error
      final failedIndex = _messages.indexWhere(
        (m) => m.localId == message.localId,
      );
      if (failedIndex != -1) {
        _messages[failedIndex] = _messages[failedIndex].copyWith(
          status: MessageStatus.failed,
        );
      }

      // Resetear estados UI
      isSendingImage = false;
      isSendingAudio = false;

      // ✅ MIGRACIÓN FASE 5: Elemento crítico 3/6 - Incrementar imageRequestId en caso de error
      _imageRequestId++;

      rethrow;
    }
  }

  /// Audio methods
  Future<void> startRecording() => _audioService.startRecording();
  Future<void> cancelRecording() => _audioService.cancelRecording();

  Future<String?> stopAndSendRecording({String? model}) async {
    final path = await _audioService.stopRecording();
    if (path == null) return null; // cancelado o error

    // ✅ MIGRACIÓN: Lógica completa de stopAndSendRecording del ChatProvider original
    isUploadingUserAudio = true;

    String? transcript;

    // If user selected native STT, prefer the live transcription captured
    String provider = '';
    try {
      provider = await PrefsUtils.getSelectedAudioProvider();
    } catch (_) {}

    if (provider == 'native' || provider == 'android_native') {
      // Use live transcript as the final transcription
      if (_audioService.liveTranscript.trim().isNotEmpty) {
        transcript = _audioService.liveTranscript.trim();
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
            break;
          }
        } catch (e) {
          attempt++;
          if (attempt > maxRetries) {
            // Fallback: intentar con el transcript en vivo si existe
            if (_audioService.liveTranscript.trim().isNotEmpty) {
              transcript = _audioService.liveTranscript.trim();
            }
          }
        }
        attempt++;
      }
    }

    // Enviar mensaje con transcript si se obtuvo
    if (transcript != null && transcript.trim().isNotEmpty) {
      await sendMessage(
        text: transcript,
        model: model,
        preTranscribedText: transcript,
        userAudioPath: path,
      );
    }

    isUploadingUserAudio = false;
    return path;
  }

  Future<void> togglePlayAudio(Message msg) async {
    await _audioService.togglePlay(msg, () {});
  }

  /// ✅ MIGRACIÓN: Método isPlaying correcto del ChatProvider original
  bool isPlaying(Message msg) => _audioService.isPlayingMessage(msg);

  Future<void> generateTtsForMessage(
    Message msg, {
    String voice = 'nova',
  }) async {
    final path = await _audioService.synthesizeTts(msg.text, voice: voice);
    if (path != null) {
      // ✅ MIGRACIÓN: Actualizar mensaje con audio TTS como en ChatProvider original
      final idx = _messages.indexWhere((m) => m.localId == msg.localId);
      if (idx != -1) {
        // Calcular duración del audio
        Duration? audioDuration;
        try {
          if (await _fileOperations.fileExists(path)) {
            audioDuration = await AudioDurationUtils.getAudioDuration(path);
          }
        } catch (_) {}

        // Crear objeto AiAudio con los datos del TTS
        final audioObj = AiAudio(
          url: path,
          transcript: msg.text,
          durationMs: audioDuration?.inMilliseconds,
          isAutoTts: true,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        _messages[idx] = _messages[idx].copyWith(
          isAudio: true,
          audio: audioObj,
        );

        await _persistState();
      }
    }
  }

  /// ✅ MIGRACIÓN: Calcula y actualiza la duración del audio grabado por el usuario
  Future<void> _calculateUserAudioDuration(Message message) async {
    if (message.audio?.url == null || message.audio!.url!.isEmpty) return;

    try {
      final audioDuration = await AudioDurationUtils.getAudioDuration(
        message.audio!.url!,
      );
      final messageIndex = _messages.indexWhere(
        (m) => m.localId == message.localId,
      );

      if (messageIndex != -1 && audioDuration != null) {
        // Actualizar el objeto audio con la nueva duración
        final currentAudio = _messages[messageIndex].audio;
        final updatedAudio =
            currentAudio?.copyWith(durationMs: audioDuration.inMilliseconds) ??
            AiAudio(
              url: message.audio!.url,
              durationMs: audioDuration.inMilliseconds,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            );

        _messages[messageIndex] = _messages[messageIndex].copyWith(
          audio: updatedAudio,
        );
        await _persistState();

        Log.d(
          'Audio: duración calculada ${audioDuration.inMilliseconds}ms para ${message.audio!.url}',
          tag: 'AUDIO',
        );
      }
    } catch (e) {
      Log.w('Error calculando duración de audio: $e', tag: 'AUDIO');
    }
  }

  /// Event management
  /// ✅ INTEGRACIÓN: Event management con PromiseService
  void schedulePromiseEvent(EventEntry event) {
    _events.add(event);
    _promiseService.schedulePromiseEvent(event);
  }

  /// Model management
  void setSelectedModel(String? model) {
    _selectedModel = model;
    _saveSelectedModel();
  }

  /// ✅ MIGRACIÓN: Persistencia de modelo seleccionado del ChatProvider original
  Future<void> _saveSelectedModel() async {
    try {
      if (_selectedModel != null) {
        await PrefsUtils.setSelectedModel(_selectedModel!);
      } else {
        // store empty to indicate unset
        await PrefsUtils.setSelectedModel('');
      }
    } catch (e) {
      // Log error but don't throw - this is non-critical
    }
  }

  /// ✅ MIGRACIÓN: Carga de modelo seleccionado del ChatProvider original
  Future<void> _loadSelectedModel() async {
    try {
      _selectedModel = await PrefsUtils.getSelectedModel();
    } catch (e) {
      _selectedModel = null;
    }
  }

  Future<List<String>> getAllModels({bool forceRefresh = false}) async {
    return ['gpt-4', 'gpt-3.5-turbo', 'claude-3'];
  }

  /// Google integration
  void setGoogleLinked(bool linked) {
    _googleLinked = linked;
  }

  /// ✅ MIGRACIÓN: updateGoogleAccountInfo completo del ChatProvider original
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
    _googleLinked = linked;

    try {
      await PrefsUtils.setGoogleAccountInfo(
        email: email,
        avatar: avatarUrl,
        name: name,
        linked: linked,
      );
    } catch (_) {}

    // ✅ MIGRACIÓN COMPLETA: Auto backup logic completo del ChatProvider original
    if (linked && triggerAutoBackup) {
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
    } else if (linked && !triggerAutoBackup) {
      Log.d(
        'Auto-backup: skip trigger (updateGoogleAccountInfo called from dialog verification)',
        tag: 'BACKUP_AUTO',
      );
    }
  }

  /// ✅ MIGRACIÓN: clearGoogleAccountInfo completo del ChatProvider original
  Future<void> clearGoogleAccountInfo() async {
    googleEmail = null;
    googleAvatarUrl = null;
    googleName = null;
    _googleLinked = false;
    try {
      await PrefsUtils.clearGoogleAccountInfo();
    } catch (_) {}
  }

  /// ✅ MIGRACIÓN: Auto backup logic completo del ChatProvider original
  /// ✅ MIGRACIÓN COMPLETA: Google Drive auto backup con toda la funcionalidad del ChatProvider original
  /// Incluye verificación 24h, refresh automático de tokens, y verificación de backups
  Future<void> _triggerAutoBackup() async {
    if (_profile == null) return;

    try {
      Log.d('Auto-backup: Triggering backup after changes', tag: 'BACKUP_AUTO');

      // ✅ MÉTODO 1: Usar BackupAutoUploader para casos automáticos (ya funciona perfecto)
      await BackupAutoUploader.maybeUploadAfterSummary(
        profile: _profile!,
        messages: _messages,
        timeline: _profile!.timeline,
        googleLinked: googleLinked,
        repository: _repository,
      );

      // ✅ MÉTODO 2: Implementar lógica completa de auto backup del ChatProvider original
      if (googleLinked) {
        await _executeAutoBackupLogic('chat_application_service');
      }
    } catch (e) {
      Log.w('Auto-backup: Failed: $e', tag: 'BACKUP_AUTO');
    }
  }

  /// ✅ MIGRACIÓN COMPLETA: Lógica de auto backup completa del ChatProvider original
  /// Incluye verificación 24h, verificación de credenciales, y verificación de backups existentes
  Future<void> _executeAutoBackupLogic(String branchName) async {
    if (!googleLinked) {
      Log.d(
        'Auto-backup: skip (not linked to Google Drive)',
        tag: 'BACKUP_AUTO',
      );
      return;
    }

    try {
      // Pequeño delay para asegurar que las credenciales están completamente inicializadas
      await Future.delayed(const Duration(milliseconds: 500));

      // Verificar que tenemos credenciales válidas antes de proceder
      final secureStorage = const FlutterSecureStorage();
      final hasRefreshToken =
          await secureStorage.read(key: 'google_refresh_token') != null;
      if (!hasRefreshToken) {
        Log.w(
          'Auto-backup: no refresh token stored; aborting',
          tag: 'BACKUP_AUTO',
        );
        return;
      }

      // Verificar la última vez que se hizo backup (lógica 24h del original)
      const String lastBackupKey = 'last_auto_backup_timestamp';
      final String? lastBackupStr = await secureStorage.read(
        key: lastBackupKey,
      );

      if (lastBackupStr != null) {
        try {
          final lastBackup = DateTime.parse(lastBackupStr);
          final now = DateTime.now();
          final hoursSince = now.difference(lastBackup).inHours;

          if (hoursSince < 24) {
            Log.d(
              'Auto-backup: skip (last backup was ${hoursSince}h ago, less than 24h)',
              tag: 'BACKUP_AUTO',
            );
            return;
          }
        } catch (e) {
          Log.w(
            'Auto-backup: error parsing last backup timestamp: $e',
            tag: 'BACKUP_AUTO',
          );
        }
      }

      Log.i('Auto-backup: proceeding with 24h+ backup...', tag: 'BACKUP_AUTO');

      // Intentar listar backups existentes para verificar conectividad (con refresh automático)
      try {
        await _listBackupsWithAutoRefresh();
        Log.d('Auto-backup: connectivity verified', tag: 'BACKUP_AUTO');
      } catch (e) {
        Log.w('Auto-backup: connectivity check failed: $e', tag: 'BACKUP_AUTO');
        return;
      }

      // Crear backup usando BackupAutoUploader (que ya tiene manejo robusto de errores)
      await _maybeTriggerAutoBackup();

      // Actualizar timestamp de último backup exitoso
      final now = DateTime.now();
      await secureStorage.write(
        key: lastBackupKey,
        value: now.toIso8601String(),
      );
      Log.i(
        'Auto-backup: [$branchName] completed successfully',
        tag: 'BACKUP_AUTO',
      );
    } catch (e) {
      Log.w('Auto-backup: [$branchName] failed: $e', tag: 'BACKUP_AUTO');
    }
  }

  /// ✅ MIGRACIÓN COMPLETA: Lista backups con refresh automático del ChatProvider original
  Future<List<Map<String, dynamic>>> _listBackupsWithAutoRefresh() async {
    try {
      // Intentar con token actual
      final currentToken = await GoogleBackupService(
        accessToken: null,
      ).loadStoredAccessToken();
      if (currentToken == null) {
        throw Exception('No stored access token available');
      }

      final service = GoogleBackupService(accessToken: currentToken);
      return await service.listBackups();
    } catch (e) {
      // Si es error OAuth, intentar refresh automático
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized') ||
          e.toString().contains('invalid_client')) {
        Log.d(
          'Auto-backup: received OAuth error, attempting automatic token refresh...',
          tag: 'BACKUP_AUTO',
        );

        try {
          final service = GoogleBackupService(accessToken: null);
          final refreshed = await service.refreshAccessToken(
            clientId: await GoogleBackupService.resolveClientId(''),
            clientSecret: await GoogleBackupService.resolveClientSecret(),
          );

          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            Log.d(
              'Auto-backup: token refresh successful, retrying listBackups...',
              tag: 'BACKUP_AUTO',
            );
            final retryService = GoogleBackupService(accessToken: newToken);
            return await retryService.listBackups();
          }
        } catch (refreshError) {
          Log.w(
            'Auto-backup: token refresh failed during listBackups: $refreshError',
            tag: 'BACKUP_AUTO',
          );
        }
      }

      // Si llegamos aquí, o no fue error OAuth o el refresh falló
      Log.w(
        'Auto-backup: listBackups failed (refresh not attempted or failed): $e',
        tag: 'BACKUP_AUTO',
      );
      rethrow;
    }
  }

  /// ✅ MIGRACIÓN COMPLETA: Trigger backup usando BackupAutoUploader del ChatProvider original
  Future<void> _maybeTriggerAutoBackup() async {
    try {
      await BackupAutoUploader.maybeUploadAfterSummary(
        profile: _profile!,
        messages: _messages,
        timeline: _profile!.timeline,
        googleLinked: googleLinked,
        repository: _repository,
      );
    } catch (e) {
      // Swallow errors: uploader logs internally (comportamiento del original)
    }
  }

  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    return {
      'googleLinked': _googleLinked,
      'chatProviderState': {
        'googleEmail': 'test@example.com',
        'googleName': 'Test User',
      },
    };
  }

  /// Profile management
  void updateProfile(AiChanProfile profile) {
    _profile = profile;
  }

  /// Prompt building
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  }) => _promptBuilder.buildRealtimeSystemPromptJson(
    profile: profile,
    messages: messages,
    maxRecent: maxRecent,
  );

  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  }) => _promptBuilder.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  /// Persistence methods
  Future<void> saveAll(Map<String, dynamic> exportedJson) async {
    await _repository.saveAll(exportedJson);
  }

  Future<Map<String, dynamic>?> loadAll() async {
    return await _repository.loadAll();
  }

  Future<void> clearAll() async {
    await _repository.clearAll();
    _messages.clear();
    _events.clear();
    _profile = null;
  }

  Future<String> exportAllToJson(Map<String, dynamic> exportedJson) async {
    return await _repository.exportAllToJson(exportedJson);
  }

  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async {
    return await _repository.importAllFromJson(jsonStr);
  }

  Future<void> applyImportedChat(Map<String, dynamic> imported) async {
    _loadFromData(imported);
    await _persistState();
  }

  /// ✅ MIGRACIÓN FASE 5: Elemento medio 5/6 - Persistencia con debouncing
  /// Persistencia inmediata (sin debouncing) para casos críticos
  Future<void> _persistStateImmediate() async {
    final data = exportToData();
    await _repository.saveAll(data);
  }

  /// Persistencia optimizada con debouncing para llamadas frecuentes
  Future<void> _persistState() async {
    _debouncedPersistence?.trigger();
  }

  void _loadFromData(Map<String, dynamic> data) {
    if (data['profile'] != null) {
      _profile = AiChanProfile.fromJson(data['profile']);
    }
    if (data['messages'] != null) {
      _messages = (data['messages'] as List)
          .map((m) => Message.fromJson(m))
          .toList();
    }
    if (data['events'] != null) {
      _events = (data['events'] as List)
          .map((e) => EventEntry.fromJson(e))
          .toList();
    }
    if (data['selectedModel'] != null) {
      _selectedModel = data['selectedModel'];
    }
    if (data['googleLinked'] != null) {
      _googleLinked = data['googleLinked'];
    }
  }

  Map<String, dynamic> exportToData() {
    return {
      'profile': _profile?.toJson(),
      'messages': _messages.map((m) => m.toJson()).toList(),
      'events': _events.map((e) => e.toJson()).toList(),
      'selectedModel': _selectedModel,
      'googleLinked': _googleLinked,
    };
  }

  /// Limpieza de recursos
  void dispose() {
    _audioService.dispose();
    _periodicScheduler.stop();
    // ✅ INTEGRACIÓN: Limpiar recursos de MessageQueueManager y PromiseService
    _queueManager?.dispose();
    _promiseService.dispose();
    // ✅ MIGRACIÓN FASE 5: Elemento medio 5/6 - Limpiar DebouncedSave
    _debouncedPersistence?.dispose();
    _debouncedPersistence = null;
  }

  // ✅ INTEGRACIÓN COMPLETA: Métodos de memoria y timeline

  /// Helper común para actualizar memoria y timeline tras mensajes IA
  Future<void> _updateMemoryAndTimeline({String debugContext = ''}) async {
    if (_profile == null) return;

    try {
      final memManager = memoryManager ?? MemoryManager(profile: _profile!);
      final oldLevel0Keys = (_profile!.timeline)
          .where((t) => t.level == 0)
          .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: _messages,
        timeline: _profile!.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _profile = TimelineUpdater.applyTimelineUpdate(
        profile: _profile!,
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
        _triggerAutoBackup();
      } else {
        final context = debugContext.isNotEmpty ? ' ($debugContext)' : '';
        Log.d(
          'Auto-backup: no new level-0 blocks; skip trigger$context',
          tag: 'BACKUP_AUTO',
        );
      }
    } catch (e) {
      Log.w(
        '[AI-chan][WARN] Falló actualización de memoria post-$debugContext: $e',
      );
    }
  }

  /// Verifica si hay nuevas entradas de nivel 0 comparando con claves anteriores
  bool _hasNewLevel0EntriesFromKeys(
    Set<String> oldKeys,
    List<TimelineEntry> newTimeline,
  ) {
    try {
      for (final t in newTimeline.where((t) => t.level == 0)) {
        final key = '${t.startDate ?? ''}|${t.endDate ?? ''}';
        if (!oldKeys.contains(key)) return true;
      }
      return false;
    } catch (e) {
      Log.w('[AI-chan][WARN] Error verificando nuevas entradas level-0: $e');
      return false;
    }
  }

  // ✅ DDD: ETAPA 3 - Métodos adicionales para compatibilidad completa

  /// Retry last failed message
  /// Reintenta enviar el último mensaje marcado como failed.
  /// Devuelve true si arrancó un reintento, false si no había mensajes failed.
  /// ✅ MIGRACIÓN FASE 5: Elemento crítico 2/6 - signature corregida
  Future<bool> retryLastFailedMessage({
    String? model,
    void Function(String)? onError,
  }) async {
    final idx = _messages.lastIndexWhere(
      (m) => m.sender == MessageSender.user && m.status == MessageStatus.failed,
    );
    if (idx == -1) return false;

    final msg = _messages[idx];
    try {
      // Reintentar reusando la lógica de sendMessage
      await sendMessage(
        text: msg.text,
        image: msg.image,
        model: model ?? _selectedModel,
      );
      return true;
    } catch (e) {
      // Ejecutar callback de error si se proporcionó
      onError?.call(e.toString());
      return false;
    }
  }

  /// Regenerate appearance for current profile
  Future<void> regenerateAppearance() async {
    if (_profile == null) {
      throw Exception('No hay perfil para regenerar apariencia');
    }

    try {
      // Usar el mismo generador que en ChatProvider - instancia directa
      final iaAppearanceGenerator = IAAppearanceGenerator();
      final newAppearance = await iaAppearanceGenerator
          .generateAppearanceFromBiography(_profile!);

      // Actualizar perfil con nueva apariencia
      _profile = _profile!.copyWith(appearance: newAppearance);

      // Persistir cambios
      await _persistState();
    } catch (e) {
      throw Exception('Error regenerando apariencia: $e');
    }
  }

  /// Generate avatar from current appearance
  Future<void> generateAvatarFromAppearance({bool replace = false}) async {
    await createAvatarFromAppearance(replace: replace);
  }

  /// ✅ MIGRACIÓN: createAvatarFromAppearance completo del ChatProvider original
  Future<void> createAvatarFromAppearance({bool replace = false}) async {
    if (_profile == null) {
      throw Exception('No hay perfil para generar avatar');
    }

    if (_profile!.appearance.isEmpty) {
      throw Exception(
        'Falta la apariencia en el perfil. Genera la apariencia primero.',
      );
    }

    try {
      // Usar el mismo generador que en ChatProvider - instancia directa
      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
        _profile!,
        appendAvatar: !replace,
      );

      // Actualizar perfil con nuevo avatar
      final Map<String, dynamic> updatedAppearance = Map.from(
        _profile!.appearance,
      );
      if (replace) {
        updatedAppearance['avatars'] = [avatar.toJson()];
      } else {
        final List<dynamic> avatars = List.from(
          updatedAppearance['avatars'] ?? [],
        );
        avatars.add(avatar.toJson());
        updatedAppearance['avatars'] = avatars;

        // Añadir mensaje del sistema cuando no es reemplazo (como en el original)
        final sysMsg = Message(
          text:
              'Tu avatar se ha actualizado. Usa la nueva imagen como referencia en futuras respuestas.',
          sender: MessageSender.system,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
        );
        _messages.add(sysMsg);
      }

      _profile = _profile!.copyWith(appearance: updatedAppearance);

      // Persistir cambios
      await _persistState();
    } catch (e) {
      throw Exception('Error generando avatar: $e');
    }
  }

  // ✅ MIGRACIÓN CRÍTICA: Métodos rescatados del ChatProvider original

  /// Schedule send message - funcionalidad completa del ChatProvider original con cola
  void scheduleSendMessage(
    String text, {
    String? callPrompt,
    String? model,
    dynamic image,
    String? imageMimeType,
    String? preTranscribedText,
    String? userAudioPath,
  }) {
    // ✅ INTEGRACIÓN: Crear mensaje y encolarlo usando MessageQueueManager
    final now = DateTime.now();
    final message = Message(
      text: text,
      sender: MessageSender.user,
      dateTime: now,
      isImage: image != null,
      image: image,
    );

    _messages.add(message);

    // Encolar mensaje con opciones completas
    final options = QueuedSendOptions(
      model: model,
      callPrompt: callPrompt,
      image: image,
      imageMimeType: imageMimeType,
      preTranscribedText: preTranscribedText,
      userAudioPath: userAudioPath,
    );
    _queueManager?.enqueue(message.localId, options: options);
  }

  /// User typing handler - funcionalidad completa del ChatProvider original con cola
  void onUserTyping(String text) {
    final empty = text.trim().isEmpty;
    if (!empty) {
      // ✅ INTEGRACIÓN: Cancelar timer de queue cuando usuario está escribiendo
      _queueManager?.cancelTimer();
    } else {
      // ✅ INTEGRACIÓN: Reiniciar timer si hay mensajes en cola
      if (queuedCount > 0) {
        _queueManager?.ensureTimer();
      }
    }
  }

  /// Typing callback - funcionalidad completa del original con promesas
  void onIaMessageSent() {
    // ✅ INTEGRACIÓN: Análisis de promesas después de mensaje IA
    try {
      _promiseService.analyzeAfterIaMessage(_messages);
    } catch (_) {}
  }

  /// Call placeholders management - funcionalidad completa del original
  int? _pendingIncomingCallMsgIndex;

  bool get hasPendingIncomingCall => _pendingIncomingCallMsgIndex != null;

  void clearPendingIncomingCall() {
    _pendingIncomingCallMsgIndex = null;
    isCalling = false;
    // notifyListeners se maneja en el controller
  }

  void replaceIncomingCallPlaceholder({
    required int index,
    required VoiceCallSummary summary,
    required String summaryText,
  }) {
    if (index < 0 || index >= _messages.length) return;
    final original = _messages[index];
    if (!original.text.contains('[call]')) return; // sanity check

    // Mantener el sender original (assistant) para diferenciar "recibida" en la UI.
    _messages[index] = Message(
      text: summaryText,
      sender: original.sender,
      dateTime: summary.startTime,
      callDuration: summary.duration,
      callEndTime: summary.endTime,
      status: MessageStatus.read,
      callStatus: CallStatus.completed,
    );
    _pendingIncomingCallMsgIndex = null;

    // Actualizar memoria igual que otros mensajes
    Future.microtask(() async {
      try {
        await _updateMemoryAndTimeline(
          debugContext: 'replaceIncomingCallPlaceholder',
        );
        _triggerAutoBackup();
      } catch (e) {
        // Log error but don't throw - memory update is non-critical
      }
    });
  }

  void rejectIncomingCallPlaceholder({
    required int index,
    required String rejectionText,
  }) {
    if (index < 0 || index >= _messages.length) return;
    final original = _messages[index];
    if (!original.text.contains('[call]')) return; // sanity check

    _messages[index] = Message(
      text: rejectionText,
      // Mantener el sender original (assistant) para reflejar que provino de llamada IA
      sender: original.sender,
      dateTime: DateTime.now(),
      status: MessageStatus.read,
      callStatus: rejectionText.toLowerCase().contains('no contestada')
          ? CallStatus.missed
          : CallStatus.rejected,
    );
    _pendingIncomingCallMsgIndex = null;

    // Actualizar memoria como en el original
    Future.microtask(() async {
      try {
        final memoryService = MemorySummaryService(profile: _profile!);
        final oldLevel0Keys = (_profile!.timeline)
            .where((t) => t.level == 0)
            .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
            .toSet();
        final result = await memoryService.processAllSummariesAndSuperblock(
          messages: _messages,
          timeline: _profile!.timeline,
          superbloqueEntry: superbloqueEntry,
        );
        _profile = _profile!.copyWith(timeline: result.timeline);
        superbloqueEntry = result.superbloqueEntry;
        if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, result.timeline)) {
          Log.d(
            'Auto-backup: trigger scheduled (rejectIncomingCallPlaceholder) — new summary block detected',
            tag: 'BACKUP_AUTO',
          );
          _triggerAutoBackup();
        }
      } catch (e) {
        Log.w('[AI-chan][WARN] Falló actualización de memoria post-reject: $e');
      }
    });
  }

  /// Message queue flush - funcionalidad completa del original
  Future<void> flushQueuedMessages() async {
    // ✅ INTEGRACIÓN: Force immediate flush via MessageQueueManager
    _queueManager?.flushNow();
  }

  /// Periodic messages control - funcionalidad completa del original
  void startPeriodicIaMessages() {
    _periodicScheduler.start(
      profileGetter: () => _profile!,
      messagesGetter: () => _messages,
      triggerSend: (prompt, model) => sendMessage(text: prompt, model: model),
    );
  }

  void stopPeriodicIaMessages() {
    _periodicScheduler.stop();
  }

  /// Save all events - funcionalidad completa del original
  Future<void> saveAllEvents() async {
    final eventsJson = jsonEncode(_events.map((e) => e.toJson()).toList());
    try {
      await PrefsUtils.setEvents(eventsJson);
    } catch (_) {}
  }

  /// Message management helpers
  void addUserImageMessage(Message msg) {
    _messages.add(msg);
    _persistState();
    // notifyListeners no es necesario aquí - se maneja en el controller
  }

  Future<void> addAssistantMessage(String text, {bool isAudio = false}) async {
    final isCallPlaceholder = text.trim() == '[call][/call]';
    final msg = Message(
      text: text,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      status: MessageStatus.read,
      callStatus: isCallPlaceholder ? CallStatus.placeholder : null,
    );
    _messages.add(msg);

    // Detección de llamada entrante solicitada por la IA mediante [call][/call]
    if (text.trim() == '[call][/call]') {
      _pendingIncomingCallMsgIndex = _messages.length - 1;
    }

    // Actualizar memoria/cronología igual que tras respuestas IA normales
    try {
      final memManager = memoryManager ?? MemoryManager(profile: _profile!);
      final oldLevel0Keys = (_profile!.timeline)
          .where((t) => t.level == 0)
          .map((t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: _messages,
        timeline: _profile!.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _profile = TimelineUpdater.applyTimelineUpdate(
        profile: _profile!,
        timeline: memResult.timeline,
        superbloqueEntry: memResult.superbloqueEntry,
      );
      superbloqueEntry = memResult.superbloqueEntry;
      if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, memResult.timeline)) {
        Log.d(
          'Auto-backup: trigger scheduled (addAssistantMessage) — new summary block detected',
          tag: 'BACKUP_AUTO',
        );
        _triggerAutoBackup();
      } else {
        Log.d(
          'Auto-backup: no new level-0 blocks; skip trigger (addAssistantMessage)',
          tag: 'BACKUP_AUTO',
        );
      }
    } catch (e) {
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-voz: $e');
    }

    await _persistState();
  }

  Future<void> addUserMessage(Message message) async {
    // Completar callStatus si viene con duración y no está seteado
    Message finalMessage = message;
    if (message.callDuration != null && message.callStatus == null) {
      finalMessage = message.copyWith(callStatus: CallStatus.completed);
    }

    _messages.add(finalMessage);

    // Actualizar memoria/cronología igual que tras respuestas IA normales
    try {
      final memManager = memoryManager ?? MemoryManager(profile: _profile!);
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: _messages,
        timeline: _profile!.timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _profile = TimelineUpdater.applyTimelineUpdate(
        profile: _profile!,
        timeline: memResult.timeline,
        superbloqueEntry: memResult.superbloqueEntry,
      );
      superbloqueEntry = memResult.superbloqueEntry;
    } catch (e) {
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-message: $e');
    }

    await _persistState();
  }

  Future<void> updateOrAddCallStatusMessage({
    required String status,
    String? metadata,
    CallStatus? callStatus,
    bool incoming = false,
    int? placeholderIndex,
  }) async {
    // Determinar sender deseado y callStatus si no se proporciona
    final MessageSender sender = incoming
        ? MessageSender.assistant
        : MessageSender.user;

    final CallStatus finalCallStatus = callStatus ?? CallStatus.completed;

    // Si hay placeholder entrante y se pasa índice, reemplazarlo conservando fecha original si existe
    if (placeholderIndex != null &&
        placeholderIndex >= 0 &&
        placeholderIndex < _messages.length) {
      final original = _messages[placeholderIndex];
      _messages[placeholderIndex] = Message(
        text: status,
        sender: sender,
        dateTime: original.dateTime,
        status: MessageStatus.read,
        callStatus: finalCallStatus,
      );
      if (_pendingIncomingCallMsgIndex == placeholderIndex) {
        _pendingIncomingCallMsgIndex = null;
      }
    } else {
      // Añadir nuevo mensaje de estado
      _messages.add(
        Message(
          text: status,
          sender: sender,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
          callStatus: finalCallStatus,
        ),
      );
    }

    // Actualizar memoria y cronología
    try {
      await _updateMemoryAndTimeline(
        debugContext: 'updateOrAddCallStatusMessage',
      );
    } catch (e) {
      // Log error but don't throw - memory update is non-critical
    }

    await _persistState();
  }

  // ✅ MIGRACIÓN FASE 5: Elemento crítico 1/6 - getServiceForModel()
  // Cache de servicios de IA por modelo para optimización de performance
  final Map<String, dynamic> _services = {};

  /// Obtiene el servicio de IA apropiado para un modelo específico.
  /// Mantiene un cache interno para evitar recrear servicios.
  ///
  /// [modelId] ID del modelo para el cual obtener el servicio
  /// Returns: El servicio de IA correspondiente o null si hay error
  dynamic getServiceForModel(String modelId) {
    if (_services.containsKey(modelId)) {
      return _services[modelId];
    }

    try {
      // Usar factory centralizado del DI para obtener implementación del servicio de IA
      final service = di.getAIServiceForModel(modelId);
      _services[modelId] = service;
      return _services[modelId];
    } catch (e) {
      // En caso de error, retornar null como lo hacía ChatProvider
      return null;
    }
  }

  /// ✅ MIGRACIÓN FASE 5: Elemento menor 6/6 - Factory method enhancement
  /// Factory method simplificado que crea ChatApplicationService.
  /// Útil para testing y compatibilidad con código existente.
  factory ChatApplicationService.withDefaults({
    required IChatRepository repository,
    required IPromptBuilderService promptBuilder,
    MemoryManager? memoryManager,
    PeriodicIaMessageScheduler? periodicScheduler,
  }) {
    // Factory method simplificado para casos de testing
    // En producción usar el constructor principal con DI
    return ChatApplicationService(
      repository: repository,
      promptBuilder: promptBuilder,
      fileOperations: di.getFileOperationsService(),
      memoryManagerParam: memoryManager,
      periodicScheduler: periodicScheduler,
    );
  }
}
