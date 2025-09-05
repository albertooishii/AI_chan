import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/core/di.dart' as di;

/// Adapter que mantiene compatibilidad con ChatProvider mientras migramos a la nueva arquitectura.
/// Esta clase implementa la misma interfaz que ChatProvider pero internamente usa ChatController + ChatApplicationService.
///
/// ⚠️ TEMPORAL: Este adapter será eliminado una vez completada la migración.
/// Su propósito es permitir una migración gradual sin romper la funcionalidad existente.
class ChatProviderAdapter extends ChangeNotifier {
  late final ChatController _controller;
  late final ChatApplicationService _service;

  // Compatibility layer - exposes the same interface as ChatProvider
  ChatProviderAdapter({ChatController? controller, ChatApplicationService? service}) {
    _service = service ?? di.getChatApplicationService();
    _controller = controller ?? ChatController(chatService: _service);

    // Forward notifications
    _controller.addListener(() => notifyListeners());
  }

  // =======================================
  // INTERFACE COMPATIBILITY WITH ChatProvider
  // =======================================

  // Messages
  List<Message> get messages => _controller.messages;

  // Profile (onboardingData in ChatProvider)
  AiChanProfile get onboardingData =>
      _controller.profile ??
      AiChanProfile(
        userName: '',
        aiName: '',
        userBirthdate: DateTime.now(),
        aiBirthdate: DateTime.now(),
        biography: {},
        appearance: {},
        timeline: [],
      );
  set onboardingData(AiChanProfile profile) => _controller.updateProfile(profile);

  // Model management
  String? get selectedModel => _controller.selectedModel;
  set selectedModel(String? model) => _controller.setSelectedModel(model);

  // Audio state
  bool get isRecording => _controller.isRecording;
  List<int> get currentWaveform => _controller.currentWaveform;
  String get liveTranscript => _controller.liveTranscript;
  Duration get recordingElapsed => _controller.recordingElapsed;
  Duration get playingPosition => _controller.playingPosition;
  Duration get playingDuration => _controller.playingDuration;
  IAudioChatService get audioService => _controller.audioService;

  // Call state
  bool get isCalling => _controller.isCalling;
  bool get hasPendingIncomingCall => _controller.hasPendingIncomingCall;

  // Google integration
  bool get googleLinked => _controller.googleLinked;

  // Events
  List<EventEntry> get events => _controller.events;

  // =======================================
  // METHOD COMPATIBILITY
  // =======================================

  /// Initializes the chat
  Future<void> loadAll() async {
    await _controller.initialize();
  }

  /// Sends a message
  Future<void> sendMessage(
    String text, {
    String? model,
    dynamic image,
    String? imageModel,
    void Function(String)? onError,
    bool isPromptAutomatic = false,
  }) async {
    await _controller.sendMessage(text: text, model: model, image: image);
  }

  /// Audio methods
  Future<void> startRecording() => _controller.startRecording();
  Future<void> cancelRecording() => _controller.cancelRecording();
  Future<void> stopAndSendRecording({String? model}) => _controller.stopAndSendRecording(model: model);
  Future<void> togglePlayAudio(Message msg, [BuildContext? context]) => _controller.togglePlayAudio(msg);
  Future<void> generateTtsForMessage(Message msg, {String voice = 'nova'}) =>
      _controller.generateTtsForMessage(msg, voice: voice);

  /// Call methods
  void setCalling(bool calling) => _controller.setCalling(calling);
  void clearPendingIncomingCall() => _controller.clearPendingIncomingCall();

  /// Event management
  void schedulePromiseEvent(EventEntry event) => _controller.schedulePromiseEvent(event);
  void onIaMessageSent() {
    // TODO: Implement IA message sent callback if needed
  }

  /// Model management
  Future<List<String>> getAllModels({bool forceRefresh = false}) =>
      _controller.getAllModels(forceRefresh: forceRefresh);

  /// Google integration
  Future<Map<String, dynamic>> diagnoseGoogleState() => _controller.diagnoseGoogleState();

  /// Import/Export
  Future<void> applyImportedChat(Map<String, dynamic> imported) => _controller.applyImportedChat(imported);

  Future<String> exportAllToJson(Map<String, dynamic> data) => _controller.exportChat();

  /// Persistence
  Future<void> saveAll() async {
    await _controller.saveState();
  }

  Future<void> clearAll() async {
    await _controller.clearMessages();
  }

  /// Prompt building
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  }) => _controller.buildRealtimeSystemPromptJson(profile: profile, messages: messages, maxRecent: maxRecent);

  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  }) => _controller.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  // =======================================
  // COMPATIBILITY METHODS - Bridge pattern
  // =======================================

  /// User typing indicator
  void onUserTyping(String text) {
    _controller.setTyping(text.isNotEmpty);
  }

  /// Periodic scheduling (legacy)
  void startPeriodicIaMessages() {
    // Implement if needed
  }

  void stopPeriodicIaMessages() {
    // Implement if needed
  }

  /// Queue management (legacy compatibility)
  int get queuedCount => 0; // Simplified for now

  void scheduleSendMessage({required String text, String? model, dynamic image}) {
    // Bridge: Queue method delegates directly to send message
    sendMessage(text, model: model, image: image);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
