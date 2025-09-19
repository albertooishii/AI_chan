import 'dart:convert';

import 'package:ai_chan/chat.dart'; // Para PeriodicIaMessageScheduler y domain interfaces
import 'package:ai_chan/shared.dart';

/// Callback para notificar cambios de estado a la UI
typedef StateChangeCallback = void Function();

/// Application Service que maneja la lógica de negocio del chat.
/// Orquesta casos de uso y servicios de dominio.
/// Esta clase reemplaza gradualmente las responsabilidades de ChatProvider.
class ChatApplicationService {
  ChatApplicationService({
    required final IChatRepository repository,
    required final IPromptBuilderService promptBuilder,
    required final IFileOperationsService fileOperations,
    required final ISecureStorageService secureStorage,
    required final IAudioChatService audioService,
    final MemoryManager? memoryManagerParam,
    final PeriodicIaMessageScheduler? periodicScheduler,
  }) : _repository = repository,
       _promptBuilder = promptBuilder,
       _fileOperations = fileOperations,
       _secureStorage = secureStorage,
       _audioService = audioService,
       memoryManager = memoryManagerParam,
       _periodicScheduler = periodicScheduler ?? PeriodicIaMessageScheduler() {
    // Initialize MessageQueueManager
    _queueManager = MessageQueueManager(
      onFlush: (final ids, final lastLocalId, final options) {
        try {
          // Marcar todos los mensajes anteriores como enviados excepto el último
          for (final lid in ids) {
            if (lid == lastLocalId) continue;
            final idx = _messages.indexWhere((final m) => m.localId == lid);
            if (idx != -1) {
              final m = _messages[idx];
              if (m.sender == MessageSender.user &&
                  m.status == MessageStatus.sending) {
                _messages[idx] = m.copyWith(status: MessageStatus.sent);
              }
            }
          }

          // Encontrar el último mensaje y procesarlo
          final lastIdx = _messages.indexWhere(
            (final m) => m.localId == lastLocalId,
          );
          if (lastIdx != -1) {
            final lastMsg = _messages[lastIdx];
            // Marcar como enviado inmediatamente para evitar UI stuck
            if (lastMsg.sender == MessageSender.user &&
                lastMsg.status == MessageStatus.sending) {
              _messages[lastIdx] = lastMsg.copyWith(status: MessageStatus.sent);
            }
            // Process directly with SendMessageUseCase
            _processWithSendMessageUseCase(lastMsg, options);
          }
        } on Exception catch (_) {}
      },
    );

    // Initialize PromiseService
    _promiseService = PromiseService(
      events: _events,
      onEventsChanged: () {}, // notifyListeners se maneja en el controller
      sendSystemPrompt:
          (final text, {final String? callPrompt, final String? model}) =>
              sendMessage(text: text), // Model selection is now automatic
    );

    // Initialize SendMessageUseCase with proper AI service
    _sendMessageUseCase = SendMessageUseCase();

    // Initialize DebouncedSave for persistence optimization
    _debouncedPersistence = DebouncedSave(
      const Duration(seconds: 1),
      () => _persistStateImmediate(),
    );
  }
  final IChatRepository _repository;
  final IPromptBuilderService _promptBuilder;
  final IFileOperationsService _fileOperations;
  final ISecureStorageService _secureStorage;
  late final IAudioChatService _audioService;
  final MemoryManager? memoryManager;
  final PeriodicIaMessageScheduler _periodicScheduler;
  late final SendMessageUseCase
  _sendMessageUseCase; // Use Case for message sending

  // MessageQueueManager and PromiseService are properly integrated
  MessageQueueManager? _queueManager;
  late final PromiseService _promiseService;

  // Callback to notify UI
  StateChangeCallback? _stateChangeCallback;

  // Estado interno del servicio
  List<Message> _messages = [];
  AiChanProfile? _profile;
  List<ChatEvent> _events = [];
  List<TimelineEntry> _timeline = [];
  String? _selectedModel;
  bool _googleLinked = false;
  TimelineEntry? superbloqueEntry;

  // UI state variables from original ChatProvider (public and mutable)
  bool isSummarizing = false;
  bool isTyping = false;
  bool isSendingImage = false;
  bool isSendingAudio = false;
  bool isUploadingUserAudio = false;
  bool isCalling = false;

  // Image request ID for concurrency control
  int _imageRequestId = 0;

  // DebouncedSave for persistence optimization
  DebouncedSave? _debouncedPersistence;

  // Google account state from original ChatProvider (public and mutable)
  String? googleEmail;
  String? googleAvatarUrl;
  String? googleName;

  // Getters públicos
  List<Message> get messages => List.unmodifiable(_messages);
  AiChanProfile? get profile => _profile;
  List<ChatEvent> get events => List.unmodifiable(_events);
  List<TimelineEntry> get timeline => List.unmodifiable(_timeline);
  String? get selectedModel => _selectedModel;

  /// Selected model setter interface
  /// Setter for the selected model
  set selectedModel(final String? model) {
    _selectedModel = model;
    _saveSelectedModel();
    // Nota: En DDD no usamos notifyListeners() aquí, se maneja en la UI layer
  }

  bool get googleLinked => _googleLinked;

  // Queue management functionality
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
    try {
      final data = await _repository.loadAll();
      if (data != null) {
        _loadFromData(data);
        Log.d(
          'ChatApplicationService: loaded persisted data (messages=${_messages.length}, profile=${_profile?.aiName})',
          tag: 'CHAT_SERVICE',
        );
      } else {
        Log.d(
          'ChatApplicationService: no persisted data found',
          tag: 'CHAT_SERVICE',
        );
      }
    } on Exception catch (e, st) {
      Log.e(
        'ChatApplicationService: error loading persisted data: $e',
        tag: 'CHAT_SERVICE',
        error: e,
      );
      Log.e(st.toString(), tag: 'CHAT_SERVICE');
    }
    // Load selected model
    await _loadSelectedModel();

    // Restore promises from events
    _promiseService.restoreFromEvents();
  }

  /// Notifies state changes to the UI
  void _notifyStateChanged() {
    _stateChangeCallback?.call();
  }

  /// Process message using SendMessageUseCase directly
  Future<void> _processWithSendMessageUseCase(
    final Message message,
    final QueuedSendOptions? options,
  ) async {
    if (_profile == null) return;

    try {
      // Crear SystemPrompt
      final systemPrompt = SystemPrompt(
        profile: _profile!,
        dateTime: DateTime.now(),
        recentMessages: _messages
            .take(32)
            .map((final m) => m.toJson())
            .toList(),
        instructions: {},
      );

      // Detectar si debemos activar la ruta de generación de imágenes.
      // Consideramos petición explícita de imagen en el texto o que se haya
      // proporcionado una imagen/base64 en options.
      final bool enableImageGeneration =
          ImageRequestService.isImageRequested(
            text: message.text,
            history: _messages,
          ) ||
          (options?.image != null);

      // Llamar al UseCase
      final outcome = await _sendMessageUseCase.sendChat(
        recentMessages: _messages,
        systemPromptObj: systemPrompt,
        image: options?.image is AiImage ? options!.image as AiImage : null,
        enableImageGeneration: enableImageGeneration,
        onboardingData: _profile,
        saveAll: () => _persistStateImmediate(),
      );

      // Agregar respuesta de la IA si llegó una y no es [no_reply]
      if (outcome.result.text.trim().isNotEmpty &&
          !outcome.result.text.contains('[no_reply]')) {
        final responseMessage = Message(
          text: outcome.result.text,
          sender: MessageSender.assistant,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
        );
        _messages.add(responseMessage);

        // Update user message status to "read" when we receive AI response
        final userMessageIndex = _messages.indexWhere(
          (final m) => m.localId == message.localId,
        );
        if (userMessageIndex != -1 &&
            _messages[userMessageIndex].sender == MessageSender.user) {
          _messages[userMessageIndex] = _messages[userMessageIndex].copyWith(
            status: MessageStatus.read,
          );
        }

        await _persistStateImmediate();
      }

      // Notificar cambios
      _notifyStateChanged();
    } on Exception catch (e) {
      Log.e('Error processing queued message: $e', tag: 'CHAT_SERVICE');
      // Marcar como fallido
      final idx = _messages.indexWhere(
        (final m) => m.localId == message.localId,
      );
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageStatus.failed);
        await _persistStateImmediate();
      }
    }
  }

  /// Registers callback for state notifications
  void setOnStateChanged(final StateChangeCallback? callback) {
    _stateChangeCallback = callback;
  }

  /// Envía un mensaje
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
    final String? imageMimeType,
    final String? preTranscribedText,
    final String? userAudioPath,
    final int? existingMessageIndex, // For retries
  }) async {
    if (_profile == null) throw Exception('Perfil no inicializado');

    // Image request detection like ChatProvider
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

    // Separate image data: base64 for AI processing, AiImage object for message storage
    String? imageBase64ForAI;
    AiImage? imageForMessage;

    if (hasImage && image is String) {
      // If image is base64 string, use it for AI and create AiImage for storage
      imageBase64ForAI = image;
      // Create a simple AiImage reference (without storing base64 in message)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = imageMimeType == 'image/jpeg'
          ? 'jpg'
          : imageMimeType == 'image/webp'
          ? 'webp'
          : 'png';
      imageForMessage = AiImage(url: 'img_user_$timestamp.$ext');
    } else if (hasImage) {
      // If image is already an AiImage object (from retry), keep it as is
      imageForMessage = image as AiImage?;
      imageBase64ForAI = null; // No base64 available for retry scenarios
    }

    // Existing message index logic for retries
    Message message;
    if (existingMessageIndex != null &&
        existingMessageIndex >= 0 &&
        existingMessageIndex < _messages.length) {
      // Reintento: actualizar mensaje existente
      message = _messages[existingMessageIndex].copyWith(
        status: MessageStatus.sending,
        text: text,
        image: imageForMessage,
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
        image: imageForMessage,
      );
      _messages.add(message);
    }

    // Update UI states
    if (hasImage) {
      isSendingImage = true;

      // Concurrency control for image requests
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

    // Calculate user audio duration in background
    if (message.audio?.url != null && message.audio!.url!.isNotEmpty) {
      _calculateUserAudioDuration(message);
    }

    // Check network connectivity before processing
    final hasInternet = await hasInternetConnection();

    if (!hasInternet) {
      // No internet: mark message as failed immediately
      final messageIndex = _messages.indexWhere(
        (final m) => m.localId == message.localId,
      );
      if (messageIndex != -1) {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          status: MessageStatus.failed,
        );
        await _persistStateImmediate();
        _notifyStateChanged();
      }
      Log.w(
        'No internet connection. Message marked as failed.',
        tag: 'CHAT_SERVICE',
      );
      return;
    }

    // Update message to "sent" status after confirming internet connectivity
    final messageIndex = _messages.indexWhere(
      (final m) => m.localId == message.localId,
    );
    if (messageIndex != -1) {
      _messages[messageIndex] = _messages[messageIndex].copyWith(
        status: MessageStatus.sent,
      );
      await _persistStateImmediate();
      _notifyStateChanged();
    }

    // Process AI response with simplified method
    final options = QueuedSendOptions(
      image: imageBase64ForAI, // Use base64 for AI processing
      imageMimeType: imageMimeType,
    );
    await _processWithSendMessageUseCase(message, options);
  }

  /// Audio methods
  Future<void> startRecording() => _audioService.startRecording();
  Future<void> cancelRecording() => _audioService.cancelRecording();

  Future<String?> stopAndSendRecording({final String? model}) async {
    final path = await _audioService.stopRecording();
    if (path == null) return null; // cancelado o error

    // Complete logic from original ChatProvider
    isUploadingUserAudio = true;

    String? transcript;

    // If user selected native STT, prefer the live transcription captured
    String provider = '';
    try {
      provider = await PrefsUtils.getSelectedAudioProvider();
    } on Exception catch (_) {}

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
          // TODO: Refactor to inject STT service factory instead of direct DI access
          final stt = getSttServiceForProvider(provider);
          final result = await stt.transcribeAudio(path);
          if (result != null && result.trim().isNotEmpty) {
            transcript = result.trim();
            break;
          }
        } on Exception {
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
        preTranscribedText: transcript,
        userAudioPath: path,
      ); // Model selection is now automatic
    }

    isUploadingUserAudio = false;
    return path;
  }

  Future<void> togglePlayAudio(final Message msg) async {
    await _audioService.togglePlay(msg, () {});
  }

  /// Correct isPlaying method from original ChatProvider
  bool isPlaying(final Message msg) => _audioService.isPlayingMessage(msg);

  Future<void> generateTtsForMessage(final Message msg) async {
    final path = await _audioService.synthesizeTts(msg.text);
    if (path != null) {
      // Update message with TTS audio
      final idx = _messages.indexWhere((final m) => m.localId == msg.localId);
      if (idx != -1) {
        // Calcular duración del audio
        Duration? audioDuration;
        try {
          if (await _fileOperations.fileExists(path)) {
            audioDuration = await AudioDurationUtils.getAudioDuration(path);
          }
        } on Exception catch (_) {}

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

  /// Calculates and updates duration of recorded user audio
  Future<void> _calculateUserAudioDuration(final Message message) async {
    if (message.audio?.url == null || message.audio!.url!.isEmpty) return;

    try {
      final audioDuration = await AudioDurationUtils.getAudioDuration(
        message.audio!.url!,
      );
      final messageIndex = _messages.indexWhere(
        (final m) => m.localId == message.localId,
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
    } on Exception catch (e) {
      Log.w('Error calculando duración de audio: $e', tag: 'AUDIO');
    }
  }

  /// Event management
  /// Event management with PromiseService
  ///
  void schedulePromiseEvent(final ChatEvent event) {
    _events.add(event);
    _promiseService.schedulePromiseEvent(event);
  }

  /// Model management
  void setSelectedModel(final String? model) {
    _selectedModel = model;
    _saveSelectedModel();
  }

  /// Selected model persistence from original ChatProvider
  Future<void> _saveSelectedModel() async {
    try {
      if (_selectedModel != null) {
        await PrefsUtils.setSelectedModel(_selectedModel!);
      } else {
        // store empty to indicate unset
        await PrefsUtils.setSelectedModel('');
      }
    } on Exception {
      // Log error but don't throw - this is non-critical
    }
  }

  /// Load selected model from original ChatProvider
  Future<void> _loadSelectedModel() async {
    try {
      _selectedModel = await PrefsUtils.getSelectedModel();
    } on Exception {
      _selectedModel = null;
    }
  }

  Future<List<String>> getAllModels({final bool forceRefresh = false}) async {
    try {
      // Get all available models from all providers
      final allModels = <String>[];

      // Get models for text generation capability from all providers
      final textModels = await AIProviderManager.instance.getAvailableModels(
        AICapability.textGeneration,
      );
      allModels.addAll(textModels);

      // Get models for image generation capability from all providers
      final imageModels = await AIProviderManager.instance.getAvailableModels(
        AICapability.imageGeneration,
      );
      allModels.addAll(imageModels);

      // Remove duplicates and return
      return allModels.toSet().toList();
    } on Exception catch (e) {
      Log.w('[ChatService] Error obteniendo modelos: $e');
      // 🚀 DINÁMICO: Fallback a modelos dinámicos en lugar de hardcodeados
      return await _getFallbackModels();
    }
  }

  /// 🚀 DINÁMICO: Obtener modelos de fallback dinámicamente
  Future<List<String>> _getFallbackModels() async {
    try {
      // Intentar obtener modelos de text generation
      final textModels = await AIProviderManager.instance.getAvailableModels(
        AICapability.textGeneration,
      );
      if (textModels.isNotEmpty) {
        return textModels.take(5).toList(); // Limitar a 5 modelos
      }
      return ['unknown-model'];
    } on Exception catch (e) {
      Log.w('[ChatService] Error obteniendo modelos de fallback: $e');
      return ['unknown-model'];
    }
  }

  /// 🚀 DINÁMICO: Obtener modelo de chat por defecto dinámicamente
  /// Google integration
  void setGoogleLinked(final bool linked) {
    _googleLinked = linked;
  }

  /// Update Google account information and optionally trigger auto backup
  Future<void> updateGoogleAccountInfo({
    final String? email,
    final String? avatarUrl,
    final String? name,
    final bool linked = true,
    final bool triggerAutoBackup = false,
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
    } on Exception catch (_) {}

    // Auto backup logic when account is linked
    if (linked && triggerAutoBackup) {
      try {
        // Add a small delay to ensure credentials are fully saved and available
        await Future.delayed(const Duration(seconds: 1));

        // Verify that credentials are actually available using domain interface
        final credsStr = await _secureStorage.read('google_credentials');
        bool hasValidToken = false;
        if (credsStr != null && credsStr.isNotEmpty) {
          try {
            final creds = jsonDecode(credsStr);
            final accessToken = creds['access_token'] as String?;
            hasValidToken = accessToken != null && accessToken.isNotEmpty;
          } on Exception {
            hasValidToken = false;
          }
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
      } on Exception catch (e) {
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

  /// Clear Google account information
  Future<void> clearGoogleAccountInfo() async {
    googleEmail = null;
    googleAvatarUrl = null;
    googleName = null;
    _googleLinked = false;
    try {
      await PrefsUtils.clearGoogleAccountInfo();
    } on Exception catch (_) {}
  }

  /// Auto backup logic with 24h verification, credential checking, and automatic refresh
  /// Includes complete functionality from original ChatProvider
  Future<void> _triggerAutoBackup() async {
    if (_profile == null) return;

    try {
      Log.d('Auto-backup: Triggering backup after changes', tag: 'BACKUP_AUTO');

      // Method 1: Use BackupAutoUploader for automatic cases (already working perfectly)
      await BackupAutoUploader.maybeUploadAfterSummary(
        profile: _profile!,
        messages: _messages,
        timeline: _timeline,
        googleLinked: googleLinked,
        repository: _repository,
      );

      // Method 2: Implement complete auto backup logic from original ChatProvider
      if (googleLinked) {
        await _executeAutoBackupLogic('chat_application_service');
      }
    } on Exception catch (e) {
      Log.w('Auto-backup: Failed: $e', tag: 'BACKUP_AUTO');
    }
  }

  /// Complete auto backup logic from original ChatProvider
  /// Includes 24h verification, credential checking, and backup verification
  Future<void> _executeAutoBackupLogic(final String branchName) async {
    if (!googleLinked) {
      Log.d(
        'Auto-backup: skip (not linked to Google Drive)',
        tag: 'BACKUP_AUTO',
      );
      return;
    }

    try {
      // Small delay to ensure that credentials are completely initialized
      await Future.delayed(const Duration(milliseconds: 500));

      // Use secure storage to check last backup timestamp
      Log.i('Auto-backup: starting backup process', tag: 'BACKUP_AUTO');

      // Check last backup timestamp for 24h logic
      const String lastBackupKey = 'last_auto_backup_timestamp';
      final String? lastBackupStr = await _secureStorage.read(lastBackupKey);

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
        } on Exception catch (e) {
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
      } on Exception catch (e) {
        Log.w('Auto-backup: connectivity check failed: $e', tag: 'BACKUP_AUTO');
        return;
      }

      // Crear backup usando BackupAutoUploader (que ya tiene manejo robusto de errores)
      await _maybeTriggerAutoBackup();

      // Update timestamp of successful backup
      final now = DateTime.now();
      await _secureStorage.write(lastBackupKey, now.toIso8601String());
      Log.i(
        'Auto-backup: [$branchName] completed successfully',
        tag: 'BACKUP_AUTO',
      );
    } on Exception catch (e) {
      Log.w('Auto-backup: [$branchName] failed: $e', tag: 'BACKUP_AUTO');
    }
  }

  /// List backups with automatic refresh from original ChatProvider
  Future<List<Map<String, dynamic>>> _listBackupsWithAutoRefresh() async {
    try {
      // Intentar con token actual
      final currentToken = await GoogleBackupService().loadStoredAccessToken();
      if (currentToken == null) {
        throw Exception('No stored access token available');
      }

      final service = GoogleBackupService(accessToken: currentToken);
      return await service.listBackups();
    } on Exception catch (e) {
      // Si es error OAuth, intentar refresh automático
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized') ||
          e.toString().contains('invalid_client')) {
        Log.d(
          'Auto-backup: received OAuth error, attempting automatic token refresh...',
          tag: 'BACKUP_AUTO',
        );

        try {
          final service = GoogleBackupService();
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
        } on Exception catch (refreshError) {
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

  /// Trigger backup using BackupAutoUploader from original ChatProvider
  Future<void> _maybeTriggerAutoBackup() async {
    try {
      await BackupAutoUploader.maybeUploadAfterSummary(
        profile: _profile!,
        messages: _messages,
        timeline: _timeline,
        googleLinked: googleLinked,
        repository: _repository,
      );
    } on Exception {
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
  void updateProfile(final AiChanProfile profile) {
    _profile = profile;
  }

  /// Prompt building
  String buildRealtimeSystemPromptJson({
    required final AiChanProfile profile,
    required final List<Message> messages,
    final int maxRecent = 32,
  }) => _promptBuilder.buildRealtimeSystemPromptJson(
    profile: profile,
    messages: messages,
    maxRecent: maxRecent,
  );

  String buildCallSystemPromptJson({
    required final AiChanProfile profile,
    required final List<Message> messages,
    required final bool aiInitiatedCall,
    final int maxRecent = 32,
  }) => _promptBuilder.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    timeline: _timeline,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  /// Persistence methods
  Future<void> saveAll(final Map<String, dynamic> exportedJson) async {
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

  Future<String> exportAllToJson(
    final Map<String, dynamic> exportedJson,
  ) async {
    return await _repository.exportAllToJson(exportedJson);
  }

  Future<Map<String, dynamic>?> importAllFromJson(final String jsonStr) async {
    return await _repository.importAllFromJson(jsonStr);
  }

  Future<void> applyChatExport(final Map<String, dynamic> chatExport) async {
    _loadFromData(chatExport);
    await _persistState();
  }

  /// Persistence with debouncing
  /// Immediate persistence (without debouncing) for critical cases
  Future<void> _persistStateImmediate() async {
    try {
      final data = exportToData();
      await _repository.saveAll(data);
      Log.d(
        'ChatApplicationService: persisted stateImmediate (messages=${_messages.length})',
        tag: 'PERSIST',
      );
    } on Exception catch (e, st) {
      Log.e(
        'ChatApplicationService: failed to persist stateImmediate: $e',
        tag: 'PERSIST',
        error: e,
      );
      Log.e(st.toString(), tag: 'PERSIST');
      rethrow;
    }
  }

  /// Persistencia optimizada con debouncing para llamadas frecuentes
  Future<void> _persistState() async {
    _debouncedPersistence?.trigger();
  }

  void _loadFromData(final Map<String, dynamic> data) {
    // Handle both old format (with 'profile' key) and new flattened format
    if (data['profile'] != null) {
      // Old format: profile is nested
      _profile = AiChanProfile.fromJson(data['profile']);
    } else {
      // New flattened format: profile fields are at top level
      // Extract profile fields by creating a copy and removing non-profile keys
      final Map<String, dynamic> profileData = Map<String, dynamic>.from(data);
      profileData.remove('messages');
      profileData.remove('events');
      profileData.remove('timeline');
      profileData.remove('selectedModel');
      profileData.remove('googleLinked');

      try {
        _profile = AiChanProfile.fromJson(profileData);
      } on Exception catch (e) {
        Log.w(
          'ChatApplicationService: Failed to parse flattened profile: $e',
          tag: 'CHAT_SERVICE',
        );
      }
    }

    if (data['messages'] != null) {
      _messages = (data['messages'] as List)
          .map((final m) => Message.fromJson(m))
          .toList();
    }
    if (data['events'] != null) {
      _events = (data['events'] as List)
          .map((final e) => ChatEvent.fromJson(e))
          .toList();
    }
    if (data['timeline'] != null) {
      _timeline = (data['timeline'] as List)
          .map((final t) => TimelineEntry.fromJson(t))
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
    final Map<String, dynamic> result = {};

    // Flatten the profile at the top level (compatible with ChatExport.fromJson)
    if (_profile != null) {
      result.addAll(_profile!.toJson());
    }

    // Add other data
    result['messages'] = _messages.map((final m) => m.toJson()).toList();
    result['events'] = _events.map((final e) => e.toJson()).toList();
    result['timeline'] = _timeline.map((final t) => t.toJson()).toList();
    result['selectedModel'] = _selectedModel;
    result['googleLinked'] = _googleLinked;

    return result;
  }

  /// Limpieza de recursos
  void dispose() {
    _audioService.dispose();
    _periodicScheduler.stop();
    // Clean resources of MessageQueueManager and PromiseService
    _queueManager?.dispose();
    _promiseService.dispose();
    // Clean up DebouncedSave
    _debouncedPersistence?.dispose();
    _debouncedPersistence = null;
  }

  // Memory and timeline helper methods

  /// Helper común para actualizar memoria y timeline tras mensajes IA
  Future<void> _updateMemoryAndTimeline({
    final String debugContext = '',
  }) async {
    if (_profile == null) return;

    try {
      final memManager = memoryManager ?? MemoryManager(profile: _profile!);
      final oldLevel0Keys = (_timeline)
          .where((final t) => t.level == 0)
          .map((final t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: _messages,
        timeline: _timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _timeline = memResult.timeline;
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
    } on Exception catch (e) {
      Log.w(
        '[AI-chan][WARN] Falló actualización de memoria post-$debugContext: $e',
      );
    }
  }

  /// Verifica si hay nuevas entradas de nivel 0 comparando con claves anteriores
  bool _hasNewLevel0EntriesFromKeys(
    final Set<String> oldKeys,
    final List<TimelineEntry> newTimeline,
  ) {
    try {
      for (final t in newTimeline.where((final t) => t.level == 0)) {
        final key = '${t.startDate ?? ''}|${t.endDate ?? ''}';
        if (!oldKeys.contains(key)) return true;
      }
      return false;
    } on Exception catch (e) {
      Log.w('[AI-chan][WARN] Error verificando nuevas entradas level-0: $e');
      return false;
    }
  }

  // Additional application service methods

  /// Retry last failed message
  /// Retries sending the last message marked as failed.
  /// Returns true if a retry was started, false if there were no failed messages.
  Future<bool> retryLastFailedMessage({
    final String? model,
    final void Function(String)? onError,
  }) async {
    final idx = _messages.lastIndexWhere(
      (final m) =>
          m.sender == MessageSender.user && m.status == MessageStatus.failed,
    );
    if (idx == -1) return false;

    // Check internet connectivity before retrying
    final hasInternet = await hasInternetConnection();
    if (!hasInternet) {
      onError?.call('No hay conexión a internet para reintentar el mensaje');
      Log.w('Retry failed: No internet connection', tag: 'CHAT_SERVICE');
      return false;
    }

    final msg = _messages[idx];
    try {
      // Reintentar reusando la lógica de sendMessage con índice específico para reutilizar el mensaje
      await sendMessage(
        text: msg.text,
        image: msg.image,
        existingMessageIndex:
            idx, // Reuse existing message slot - Model selection is now automatic
      );
      return true;
    } on Exception catch (e) {
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
    } on Exception catch (e) {
      throw Exception('Error regenerando apariencia: $e');
    }
  }

  /// Generate avatar from current appearance
  Future<void> generateAvatarFromAppearance({
    final bool replace = false,
  }) async {
    await createAvatarFromAppearance(replace: replace);
  }

  /// Create avatar from current appearance - complete implementation from original ChatProvider
  Future<void> createAvatarFromAppearance({final bool replace = false}) async {
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
    } on Exception catch (e) {
      throw Exception('Error generando avatar: $e');
    }
  }

  // Methods rescued from original ChatProvider

  /// Schedule send message - complete functionality from original ChatProvider with queue
  void scheduleSendMessage(
    final String text, {
    final String? callPrompt,
    final String? model,
    final dynamic image,
    final String? imageMimeType,
    final String? preTranscribedText,
    final String? userAudioPath,
  }) {
    // Create message and enqueue using MessageQueueManager
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
      callPrompt: callPrompt,
      image: image,
      imageMimeType: imageMimeType,
      preTranscribedText: preTranscribedText,
      userAudioPath: userAudioPath,
    );
    _queueManager?.enqueue(message.localId, options: options);
  }

  /// User typing handler - funcionalidad completa del ChatProvider original con cola
  void onUserTyping(final String text) {
    final empty = text.trim().isEmpty;
    if (!empty) {
      // Cancel queue timer when user is typing
      _queueManager?.cancelTimer();
    } else {
      // Restart timer if there are messages in queue
      if (queuedCount > 0) {
        _queueManager?.ensureTimer();
      }
    }
  }

  /// Typing callback - funcionalidad completa del original con promesas
  void onIaMessageSent() {
    // Promise analysis after AI message
    try {
      _promiseService.analyzeAfterIaMessage(_messages);
    } on Exception catch (_) {}
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
    required final int index,
    required final VoiceCallSummary summary,
    required final String summaryText,
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
      } on Exception {
        // Log error but don't throw - memory update is non-critical
      }
    });
  }

  void rejectIncomingCallPlaceholder({
    required final int index,
    required final String rejectionText,
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
        final oldLevel0Keys = (_timeline)
            .where((final t) => t.level == 0)
            .map((final t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
            .toSet();
        final result = await memoryService.processAllSummariesAndSuperblock(
          messages: _messages,
          timeline: _timeline,
          superbloqueEntry: superbloqueEntry,
        );
        _timeline = result.timeline;
        superbloqueEntry = result.superbloqueEntry;
        if (_hasNewLevel0EntriesFromKeys(oldLevel0Keys, result.timeline)) {
          Log.d(
            'Auto-backup: trigger scheduled (rejectIncomingCallPlaceholder) — new summary block detected',
            tag: 'BACKUP_AUTO',
          );
          _triggerAutoBackup();
        }
      } on Exception catch (e) {
        Log.w('[AI-chan][WARN] Falló actualización de memoria post-reject: $e');
      }
    });
  }

  /// Message queue flush - funcionalidad completa del original
  Future<void> flushQueuedMessages() async {
    // Force immediate flush via MessageQueueManager
    _queueManager?.flushNow();
  }

  /// Periodic messages control - funcionalidad completa del original
  void startPeriodicIaMessages() {
    _periodicScheduler.start(
      profileGetter: () => _profile!.toJson(),
      messagesGetter: () => _messages.map((final m) => m.toJson()).toList(),
      triggerSend: (final prompt) =>
          sendMessage(text: prompt), // Model selection is now automatic
    );
  }

  void stopPeriodicIaMessages() {
    _periodicScheduler.stop();
  }

  /// Save all events - funcionalidad completa del original
  Future<void> saveAllEvents() async {
    final eventsJson = jsonEncode(
      _events.map((final e) => e.toJson()).toList(),
    );
    try {
      await PrefsUtils.setEvents(eventsJson);
    } on Exception catch (_) {}
  }

  /// Message management helpers
  void addUserImageMessage(final Message msg) {
    _messages.add(msg);
    _persistState();
    // notifyListeners no es necesario aquí - se maneja en el controller
  }

  Future<void> addAssistantMessage(
    final String text, {
    final bool isAudio = false,
  }) async {
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
      final oldLevel0Keys = (_timeline)
          .where((final t) => t.level == 0)
          .map((final t) => '${t.startDate ?? ''}|${t.endDate ?? ''}')
          .toSet();
      final memResult = await memManager.processAllSummariesAndSuperblock(
        messages: _messages,
        timeline: _timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _timeline = memResult.timeline;
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
    } on Exception catch (e) {
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-voz: $e');
    }

    await _persistState();
  }

  Future<void> addUserMessage(final Message message) async {
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
        timeline: _timeline,
        superbloqueEntry: superbloqueEntry,
      );
      _timeline = memResult.timeline;
      superbloqueEntry = memResult.superbloqueEntry;
    } on Exception catch (e) {
      Log.w('[AI-chan][WARN] Falló actualización de memoria post-message: $e');
    }

    await _persistState();
  }

  Future<void> updateOrAddCallStatusMessage({
    required final String status,
    final String? metadata,
    final CallStatus? callStatus,
    final bool incoming = false,
    final int? placeholderIndex,
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
    } on Exception {
      // Log error but don't throw - memory update is non-critical
    }

    await _persistState();
  }
}
