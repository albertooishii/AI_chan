import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

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
/// - UI State Management: Via mixin pattern
class ChatDataController extends ChangeNotifier with UIStateManagementMixin {
  ChatDataController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Data state getters
  AiChanProfile? get profile => _chatService.profile;
  List<EventEntry> get events => _chatService.events;
  List<TimelineEntry> get timeline => _chatService.timeline;
  String? get selectedModel => _chatService.selectedModel;

  /// Profile management
  void updateProfile(final AiChanProfile profile) {
    executeSyncWithNotification(
      operation: () => _chatService.updateProfile(profile),
    );
  }

  /// Model management
  void setModel(final String model) {
    executeSyncWithNotification(
      operation: () => _chatService.selectedModel = model,
    );
  }

  void clearModel() {
    executeSyncWithNotification(
      operation: () => _chatService.selectedModel = null,
    );
  }

  /// Data export operations
  Future<String> exportAllToJson(final Map<String, dynamic> data) async {
    return await _chatService.exportAllToJson(data);
  }

  /// Save all events
  Future<void> saveAllEvents() async {
    await executeWithNotification(
      operation: () => _chatService.saveAllEvents(),
      errorMessage: 'Error al guardar eventos',
    );
  }

  /// Regenerate appearance
  Future<void> regenerateAppearance() async {
    await executeWithState(
      operation: () => _chatService.regenerateAppearance(),
      errorMessage: 'Error al regenerar apariencia',
    );
  }

  /// Generate avatar from appearance
  Future<void> generateAvatarFromAppearance({
    final bool replace = false,
  }) async {
    await executeWithState(
      operation: () =>
          _chatService.generateAvatarFromAppearance(replace: replace),
      errorMessage: 'Error al generar avatar',
    );
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
