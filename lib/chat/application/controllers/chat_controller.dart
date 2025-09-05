import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

/// Controller para la UI del chat.
/// Maneja estado de presentación y eventos de usuario.
/// NO contiene lógica de negocio.
/// Esta clase reemplaza gradualmente ChatProvider en la capa de presentación.
class ChatController extends ChangeNotifier {
  final ChatApplicationService _chatService;

  // Estado UI
  bool _isLoading = false;
  String? _errorMessage;
  bool _isTyping = false;
  bool _isCalling = false;

  // Getters para UI
  List<Message> get messages => _chatService.messages;
  AiChanProfile? get profile => _chatService.profile;
  List<EventEntry> get events => _chatService.events;
  String? get selectedModel => _chatService.selectedModel;
  bool get googleLinked => _chatService.googleLinked;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTyping => _isTyping;
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

  ChatController({required ChatApplicationService chatService})
    : _chatService = chatService;

  /// Inicializa el chat cargando datos
  Future<void> initialize() async {
    _setLoading(true);
    try {
      await _chatService.initialize();
      _clearError();
    } catch (e) {
      _setError('Error al cargar chat: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Envía un mensaje
  Future<void> sendMessage({
    required String text,
    String? model,
    dynamic image,
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      _setError('Error al guardar: $e');
    }
  }

  /// Audio methods - delegates to service
  Future<void> startRecording() async {
    try {
      await _chatService.startRecording();
      notifyListeners();
    } catch (e) {
      _setError('Error al iniciar grabación: $e');
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _chatService.cancelRecording();
      notifyListeners();
    } catch (e) {
      _setError('Error al cancelar grabación: $e');
    }
  }

  Future<void> stopAndSendRecording({String? model}) async {
    try {
      final path = await _chatService.stopAndSendRecording(model: model);
      if (path != null) {
        // Procesar audio grabado
      }
      notifyListeners();
    } catch (e) {
      _setError('Error al procesar grabación: $e');
    }
  }

  Future<void> togglePlayAudio(Message msg) async {
    try {
      await _chatService.togglePlayAudio(msg);
      notifyListeners();
    } catch (e) {
      _setError('Error al reproducir audio: $e');
    }
  }

  Future<void> generateTtsForMessage(
    Message msg, {
    String voice = 'nova',
  }) async {
    try {
      await _chatService.generateTtsForMessage(msg, voice: voice);
      notifyListeners();
    } catch (e) {
      _setError('Error al generar TTS: $e');
    }
  }

  /// Model management
  void setSelectedModel(String? model) {
    _chatService.setSelectedModel(model);
    notifyListeners();
  }

  Future<List<String>> getAllModels({bool forceRefresh = false}) async {
    return await _chatService.getAllModels(forceRefresh: forceRefresh);
  }

  /// Event management
  void schedulePromiseEvent(EventEntry event) {
    _chatService.schedulePromiseEvent(event);
    notifyListeners();
  }

  /// Google integration
  void setGoogleLinked(bool linked) {
    _chatService.setGoogleLinked(linked);
    notifyListeners();
  }

  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    return await _chatService.diagnoseGoogleState();
  }

  /// Import/Export
  Future<void> applyImportedChat(Map<String, dynamic> imported) async {
    _setLoading(true);
    try {
      await _chatService.applyImportedChat(imported);
      _clearError();
      notifyListeners();
    } catch (e) {
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
  void setCalling(bool calling) {
    _isCalling = calling;
    notifyListeners();
  }

  void setPendingIncomingCall(bool pending) {
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
  void setTyping(bool typing) {
    _isTyping = typing;
    notifyListeners();
  }

  /// Profile management
  void updateProfile(AiChanProfile profile) {
    _chatService.updateProfile(profile);
    notifyListeners();
  }

  /// Prompt building (delegated)
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  }) => _chatService.buildRealtimeSystemPromptJson(
    profile: profile,
    messages: messages,
    maxRecent: maxRecent,
  );

  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  }) => _chatService.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  // Métodos privados para manejo de estado UI
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ✅ DDD: ETAPA 3 - Métodos adicionales para compatibilidad con ChatScreen

  /// User typing indicator
  void onUserTyping(String text) {
    _chatService.onUserTyping(text);
    setTyping(text.isNotEmpty);
  }

  /// Schedule sending a message (legacy compatibility)
  void scheduleSendMessage(
    String text, {
    String? model,
    dynamic image,
    String? imageMimeType,
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
    } catch (e) {
      _setError('Error al guardar eventos: $e');
    }
  }

  /// Retry last failed message
  Future<void> retryLastFailedMessage({String? model}) async {
    try {
      _setLoading(true);
      _clearError();
      await _chatService.retryLastFailedMessage(model: model);
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Helper method to execute async operations with loading state management
  Future<void> _executeWithLoadingState(
    Future<void> Function() operation,
  ) async {
    try {
      _setLoading(true);
      _clearError();
      await operation();
      notifyListeners();
    } catch (e) {
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
  Future<void> generateAvatarFromAppearance({bool replace = false}) async {
    await _executeWithLoadingState(
      () => _chatService.generateAvatarFromAppearance(replace: replace),
    );
  }

  // ✅ COMPATIBILITY: Audio playback methods
  bool isPlaying(Message msg) {
    // ✅ MIGRACIÓN: Usar método correcto del ChatApplicationService
    return _chatService.isPlaying(msg);
  }

  // ✅ COMPATIBILITY: Sending state getters
  bool get isSendingImage => _chatService.isSendingImage;
  bool get isSendingAudio => _chatService.isSendingAudio;
  bool get isUploadingUserAudio => _chatService.isUploadingUserAudio;

  // ✅ MIGRACIÓN CRÍTICA: Métodos faltantes del ChatProvider original

  /// Añade un mensaje de imagen del usuario
  void addUserImageMessage(Message msg) {
    _chatService.addUserImageMessage(msg);
    notifyListeners();
  }

  /// Añade un mensaje del asistente
  Future<void> addAssistantMessage(String text, {bool isAudio = false}) async {
    try {
      await _chatService.addAssistantMessage(text, isAudio: isAudio);
      notifyListeners();
    } catch (e) {
      _setError('Error al añadir mensaje del asistente: $e');
    }
  }

  /// Añade mensaje de usuario
  Future<void> addUserMessage(Message message) async {
    try {
      await _chatService.addUserMessage(message);
      notifyListeners();
    } catch (e) {
      _setError('Error al añadir mensaje de usuario: $e');
    }
  }

  /// Actualiza o añade mensaje de estado de llamada
  Future<void> updateOrAddCallStatusMessage({
    required String status,
    String? metadata,
    CallStatus? callStatus,
    bool incoming = false,
    int? placeholderIndex,
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
    } catch (e) {
      _setError('Error al actualizar estado de llamada: $e');
    }
  }

  /// Reemplaza placeholder de llamada entrante
  void replaceIncomingCallPlaceholder({
    required int index,
    required VoiceCallSummary summary,
    required String summaryText,
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
    required int index,
    required String rejectionText,
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
    } catch (e) {
      _setError('Error al enviar mensajes en cola: $e');
    }
  }

  /// Getters de estado de llamadas del ChatProvider original
  bool get hasPendingIncomingCall => _chatService.hasPendingIncomingCall;
  int get queuedCount => _chatService.queuedCount;

  /// Actualizar información de cuenta Google
  Future<void> updateGoogleAccountInfo({
    String? email,
    String? avatarUrl,
    String? name,
    bool linked = true,
    bool triggerAutoBackup = false,
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
    } catch (e) {
      _setError('Error al actualizar cuenta Google: $e');
    }
  }

  /// Limpiar información de cuenta Google
  Future<void> clearGoogleAccountInfo() async {
    try {
      await _chatService.clearGoogleAccountInfo();
      notifyListeners();
    } catch (e) {
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
