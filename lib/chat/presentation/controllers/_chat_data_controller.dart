import 'package:flutter/material.dart';
import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

/// 💾 **Chat Data Controller** - DDD Specialized Controller
///
/// Handles all data and configuration operations:
/// - Profile management
/// - Model selection and management
/// - Data export/import operations
/// - Event logging and timeline
/// - System configuration
///
/// **DDD Principles:**
/// - Single Responsibility: Only data/config operations
/// - Delegation: All logic delegated to ChatApplicationService
class ChatDataController extends ChangeNotifier {
  ChatDataController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Data state getters
  AiChanProfile? get profile => _chatService.profile;
  List<ChatEvent> get events => _chatService.events;
  List<TimelineEntry> get timeline => _chatService.timeline;
  String? get selectedModel => _chatService.selectedModel;

  /// Profile management
  void updateProfile(final AiChanProfile profile) {
    try {
      _chatService.updateProfile(profile);
      notifyListeners(); // Notificar cambios en el perfil
    } on Exception catch (e) {
      debugPrint('Error in updateProfile: $e');
    }
  }

  /// Model management
  void setModel(final String model) {
    try {
      _chatService.selectedModel = model;
      notifyListeners(); // Notificar cambios en el modelo seleccionado
    } on Exception catch (e) {
      debugPrint('Error in setModel: $e');
    }
  }

  void clearModel() {
    try {
      _chatService.selectedModel = null;
      notifyListeners(); // Notificar cambios en el modelo seleccionado
    } on Exception catch (e) {
      debugPrint('Error in clearModel: $e');
    }
  }

  /// Data export operations
  Future<String> exportAllToJson(final Map<String, dynamic> data) async {
    try {
      return await _chatService.exportAllToJson(data);
    } on Exception catch (e) {
      debugPrint('Error in exportAllToJson: $e');
      rethrow;
    }
  }

  /// Save all events
  Future<void> saveAllEvents() async {
    try {
      await _chatService.saveAllEvents();
    } on Exception catch (e) {
      debugPrint('Error in saveAllEvents: $e');
      rethrow;
    }
  }

  /// Regenerate appearance
  Future<void> regenerateAppearance() async {
    try {
      await _chatService.regenerateAppearance();
      notifyListeners(); // Notificar cambios en la apariencia
    } on Exception catch (e) {
      debugPrint('Error in regenerateAppearance: $e');
      rethrow;
    }
  }

  /// Generate avatar from appearance
  Future<void> generateAvatarFromAppearance({
    final bool replace = false,
  }) async {
    try {
      await _chatService.generateAvatarFromAppearance(replace: replace);
      notifyListeners(); // Notificar cambios en el avatar
    } on Exception catch (e) {
      debugPrint('Error in generateAvatarFromAppearance: $e');
      rethrow;
    }
  }

  /// Prompt building operations
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

  @override
  void dispose() {
    // Data service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
