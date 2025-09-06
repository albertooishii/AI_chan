import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

/// Controller para la UI del chat.
/// Maneja estado de presentación y eventos de usuario.
/// NO contiene lógica de negocio.
/// Esta clase reemplaza gradualmente ChatProvider en la capa de presentación.
class ChatController extends ChangeNotifier {
  ChatController({required final ChatApplicationService chatService})
    : _chatService = chatService;
  final ChatApplicationService _chatService;

  // Estado UI
  bool _isLoading = false;
  String? _errorMessage;
  bool _isCalling = false;

  // Getters para UI
  List<Message> get messages => _chatService.messages;
  AiChanProfile? get profile => _chatService.profile;
  List<EventEntry> get events => _chatService.events;
  List<TimelineEntry> get timeline => _chatService.timeline;
  String? get selectedModel => _chatService.selectedModel;
  bool get googleLinked => _chatService.googleLinked;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTyping => _chatService.isTyping;
  bool get isCalling => _isCalling;

  // Audio UI state
  bool get isRecording => _chatService.isRecording;
  List<int> get currentWaveform => _chatService.currentWaveform;
  String get liveTranscript => _chatService.liveTranscript;
  Duration get recordingElapsed => _chatService.recordingElapsed;
  Duration get playingPosition => _chatService.playingPosition;
  Duration get playingDuration => _chatService.playingDuration;

  // Direct access to audio service for UI components
  IAudioChatService get audioService => _chatService.audioService;

  /// Inicializa el chat cargando datos
  Future<void> initialize() async {
    _setLoading(true);
    try {
      await _chatService.initialize();
      _clearError();
    } on Exception catch (e) {
      _setError('Error al cargar chat: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Envía un mensaje
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  }) async {
    if (_chatService.profile == null) {
      _setError('Perfil no inicializado');
      return;
    }

    _setLoading(true);
    try {
      await _chatService.sendMessage(text: text, model: model, image: image);
      _clearError();
      notifyListeners(); // Notificar cambios en mensajes
    } on Exception catch (e) {
      _setError('Error al enviar mensaje: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Limpia todos los mensajes
  Future<void> clearMessages() async {
    _setLoading(true);
    try {
      await _chatService.clearAll();
      _clearError();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al limpiar mensajes: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Guarda el estado actual
  Future<void> saveState() async {
    try {
      final data = _chatService.exportToData();
      await _chatService.saveAll(data);
      _clearError();
    } on Exception catch (e) {
      _setError('Error al guardar: $e');
    }
  }

  /// Audio methods - delegates to service
  Future<void> startRecording() async {
    try {
      await _chatService.startRecording();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al iniciar grabación: $e');
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _chatService.cancelRecording();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al cancelar grabación: $e');
    }
  }

  Future<void> stopAndSendRecording({final String? model}) async {
    try {
      final path = await _chatService.stopAndSendRecording(model: model);
      if (path != null) {
        // Procesar audio grabado
      }
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al procesar grabación: $e');
    }
  }

  Future<void> togglePlayAudio(final Message msg) async {
    try {
      await _chatService.togglePlayAudio(msg);
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al reproducir audio: $e');
    }
  }

  Future<void> generateTtsForMessage(
    final Message msg, {
    final String voice = 'nova',
  }) async {
    try {
      await _chatService.generateTtsForMessage(msg, voice: voice);
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al generar TTS: $e');
    }
  }

  /// Model management
  void setSelectedModel(final String? model) {
    _chatService.setSelectedModel(model);
    notifyListeners();
  }

  Future<List<String>> getAllModels({final bool forceRefresh = false}) async {
    return await _chatService.getAllModels(forceRefresh: forceRefresh);
  }

  /// Event management
  void schedulePromiseEvent(final EventEntry event) {
    _chatService.schedulePromiseEvent(event);
    notifyListeners();
  }

  /// Google integration
  void setGoogleLinked(final bool linked) {
    _chatService.setGoogleLinked(linked);
    notifyListeners();
  }

  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    return await _chatService.diagnoseGoogleState();
  }

  /// Import/Export
  Future<void> applyChatExport(final Map<String, dynamic> chatExport) async {
    _setLoading(true);
    try {
      await _chatService.applyChatExport(chatExport);
      _clearError();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al importar chat: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<String> exportChat() async {
    final data = _chatService.exportToData();
    return await _chatService.exportAllToJson(data);
  }

  /// Call state management (UI only)
  void setCalling(final bool calling) {
    _isCalling = calling;
    notifyListeners();
  }

  void setPendingIncomingCall(final bool pending) {
    // Delegado al service
    if (!pending) {
      _chatService.clearPendingIncomingCall();
    }
    notifyListeners();
  }

  void clearPendingIncomingCall() {
    _chatService.clearPendingIncomingCall();
    notifyListeners();
  }

  /// Typing indicator
  void setTyping(final bool typing) {
    // Delegate to underlying service so a single source of truth exists.
    _chatService.isTyping = typing;
    notifyListeners();
  }

  /// Profile management
  void updateProfile(final AiChanProfile profile) {
    _chatService.updateProfile(profile);
    notifyListeners();
  }

  /// Prompt building (delegated)
  String buildRealtimeSystemPromptJson({
    required final AiChanProfile profile,
    required final List<Message> messages,
    final int maxRecent = 32,
  }) => _chatService.buildRealtimeSystemPromptJson(
    profile: profile,
    messages: messages,
    maxRecent: maxRecent,
  );

  String buildCallSystemPromptJson({
    required final AiChanProfile profile,
    required final List<Message> messages,
    required final bool aiInitiatedCall,
    final int maxRecent = 32,
  }) => _chatService.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  // Métodos privados para manejo de estado UI
  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ✅ DDD: ETAPA 3 - Métodos adicionales para compatibilidad con ChatScreen

  /// User typing indicator
  void onUserTyping(final String text) {
    // Only inform service about user typing (to cancel queue timers etc.).
    // Do NOT mark the UI "isTyping" here: that flag is reserved for when
    // the assistant/IA is actually sending a response.
    _chatService.onUserTyping(text);
  }

  /// Schedule sending a message (legacy compatibility)
  void scheduleSendMessage(
    final String text, {
    final String? model,
    final dynamic image,
    final String? imageMimeType,
  }) {
    _chatService.scheduleSendMessage(
      text,
      model: model,
      image: image,
      imageMimeType: imageMimeType,
    );
    notifyListeners();
  }

  /// Control de mensajes periódicos de IA
  void startPeriodicIaMessages() {
    _chatService.startPeriodicIaMessages();
  }

  void stopPeriodicIaMessages() {
    _chatService.stopPeriodicIaMessages();
  }

  /// Guardar todos los eventos
  Future<void> saveAllEvents() async {
    try {
      await _chatService.saveAllEvents();
    } on Exception catch (e) {
      _setError('Error al guardar eventos: $e');
    }
  }

  /// Retry last failed message
  Future<void> retryLastFailedMessage({final String? model}) async {
    try {
      _setLoading(true);
      _clearError();
      await _chatService.retryLastFailedMessage(model: model);
      notifyListeners();
    } on Exception catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Helper method to execute async operations with loading state management
  Future<void> _executeWithLoadingState(
    final Future<void> Function() operation,
  ) async {
    try {
      _setLoading(true);
      _clearError();
      await operation();
      notifyListeners();
    } on Exception catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Regenerate appearance
  Future<void> regenerateAppearance() async {
    await _executeWithLoadingState(() => _chatService.regenerateAppearance());
  }

  /// Generate avatar from appearance
  Future<void> generateAvatarFromAppearance({
    final bool replace = false,
  }) async {
    await _executeWithLoadingState(
      () => _chatService.generateAvatarFromAppearance(replace: replace),
    );
  }

  // ✅ COMPATIBILITY: Audio playback methods
  bool isPlaying(final Message msg) {
    // ✅ MIGRACIÓN: Usar método correcto del ChatApplicationService
    return _chatService.isPlaying(msg);
  }

  // ✅ COMPATIBILITY: Sending state getters
  bool get isSendingImage => _chatService.isSendingImage;
  bool get isSendingAudio => _chatService.isSendingAudio;
  bool get isUploadingUserAudio => _chatService.isUploadingUserAudio;

  // ✅ MIGRACIÓN CRÍTICA: Métodos faltantes del ChatProvider original

  /// Añade un mensaje de imagen del usuario
  void addUserImageMessage(final Message msg) {
    _chatService.addUserImageMessage(msg);
    notifyListeners();
  }

  /// Añade un mensaje del asistente
  Future<void> addAssistantMessage(
    final String text, {
    final bool isAudio = false,
  }) async {
    try {
      await _chatService.addAssistantMessage(text, isAudio: isAudio);
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al añadir mensaje del asistente: $e');
    }
  }

  /// Añade mensaje de usuario
  Future<void> addUserMessage(final Message message) async {
    try {
      await _chatService.addUserMessage(message);
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al añadir mensaje de usuario: $e');
    }
  }

  /// Actualiza o añade mensaje de estado de llamada
  Future<void> updateOrAddCallStatusMessage({
    required final String status,
    final String? metadata,
    final CallStatus? callStatus,
    final bool incoming = false,
    final int? placeholderIndex,
  }) async {
    try {
      await _chatService.updateOrAddCallStatusMessage(
        status: status,
        metadata: metadata,
        callStatus: callStatus,
        incoming: incoming,
        placeholderIndex: placeholderIndex,
      );
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al actualizar estado de llamada: $e');
    }
  }

  /// Reemplaza placeholder de llamada entrante
  void replaceIncomingCallPlaceholder({
    required final int index,
    required final VoiceCallSummary summary,
    required final String summaryText,
  }) {
    _chatService.replaceIncomingCallPlaceholder(
      index: index,
      summary: summary,
      summaryText: summaryText,
    );
    notifyListeners();
  }

  /// Rechaza placeholder de llamada entrante
  void rejectIncomingCallPlaceholder({
    required final int index,
    required final String rejectionText,
  }) {
    _chatService.rejectIncomingCallPlaceholder(
      index: index,
      rejectionText: rejectionText,
    );
    notifyListeners();
  }

  /// Fuerza el envío de mensajes en cola
  Future<void> flushQueuedMessages() async {
    try {
      await _chatService.flushQueuedMessages();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al enviar mensajes en cola: $e');
    }
  }

  /// Getters de estado de llamadas del ChatProvider original
  bool get hasPendingIncomingCall => _chatService.hasPendingIncomingCall;
  int get queuedCount => _chatService.queuedCount;

  /// Actualizar información de cuenta Google
  Future<void> updateGoogleAccountInfo({
    final String? email,
    final String? avatarUrl,
    final String? name,
    final bool linked = true,
    final bool triggerAutoBackup = false,
  }) async {
    try {
      await _chatService.updateGoogleAccountInfo(
        email: email,
        avatarUrl: avatarUrl,
        name: name,
        linked: linked,
        triggerAutoBackup: triggerAutoBackup,
      );
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al actualizar cuenta Google: $e');
    }
  }

  /// Limpiar información de cuenta Google
  Future<void> clearGoogleAccountInfo() async {
    try {
      await _chatService.clearGoogleAccountInfo();
      notifyListeners();
    } on Exception catch (e) {
      _setError('Error al limpiar cuenta Google: $e');
    }
  }

  /// Getters de cuenta Google del ChatProvider original
  String? get googleEmail => _chatService.googleEmail;
  String? get googleAvatarUrl => _chatService.googleAvatarUrl;
  String? get googleName => _chatService.googleName;

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }
}
