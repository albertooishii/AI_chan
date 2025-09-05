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
  bool _hasPendingIncomingCall = false;

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
  bool get hasPendingIncomingCall => _hasPendingIncomingCall;

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
    _hasPendingIncomingCall = pending;
    notifyListeners();
  }

  void clearPendingIncomingCall() {
    _hasPendingIncomingCall = false;
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

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }
}
