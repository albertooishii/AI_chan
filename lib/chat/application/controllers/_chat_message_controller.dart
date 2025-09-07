import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

/// 💬 **Chat Message Controller** - DDD Specialized Controller
///
/// Handles all message-related functionality:
/// - Message creation (user, assistant, system)
/// - Message lifecycle (add, retry, regenerate)
/// - Message scheduling and queueing
/// - Message typing indicators
/// - Message state management
///
/// **DDD Principles:**
/// - Single Responsibility: Only message operations
/// - Delegation: All logic delegated to ChatApplicationService
/// - UI State Management: Via mixin pattern
class ChatMessageController extends ChangeNotifier with UIStateManagementMixin {
  ChatMessageController({required final ChatApplicationService chatService}) : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Message state getters
  bool get isTyping => _chatService.isTyping;
  bool get isSendingImage => _chatService.isSendingImage;

  /// User typing indicator
  void onUserTyping(final String text) {
    // Only inform service about user typing (to cancel queue timers etc.).
    // Do NOT mark the UI "isTyping" here: that flag is reserved for when
    // the assistant/IA is actually sending a response.
    executeSyncWithNotification(operation: () => _chatService.onUserTyping(text));
  }

  /// Typing indicator
  void setTyping(final bool typing) {
    // Delegate to underlying service so a single source of truth exists.
    executeSyncWithNotification(operation: () => _chatService.isTyping = typing);
  }

  /// Schedule sending a message (legacy compatibility)
  void scheduleSendMessage(final String text, {final String? model, final dynamic image, final String? imageMimeType}) {
    executeSyncWithNotification(
      operation: () => _chatService.scheduleSendMessage(text, model: model, image: image, imageMimeType: imageMimeType),
    );
  }

  /// Add user image message
  void addUserImageMessage(final Message msg) {
    executeSyncWithNotification(operation: () => _chatService.addUserImageMessage(msg));
  }

  /// Add assistant message
  Future<void> addAssistantMessage(final String text, {final bool isAudio = false}) async {
    await delegate(
      serviceCall: () => _chatService.addAssistantMessage(text, isAudio: isAudio),
      errorMessage: 'Error al añadir mensaje del asistente',
    );
  }

  /// Add user message
  Future<void> addUserMessage(final Message message) async {
    await delegate(
      serviceCall: () => _chatService.addUserMessage(message),
      errorMessage: 'Error al añadir mensaje de usuario',
    );
  }

  /// Retry last failed message
  Future<void> retryLastFailedMessage({final String? model}) async {
    await executeWithState(
      operation: () => _chatService.retryLastFailedMessage(model: model),
      errorMessage: 'Error al reintentar mensaje',
    );
  }

  /// Control de mensajes periódicos de IA
  void startPeriodicIaMessages() {
    executeSyncWithNotification(operation: () => _chatService.startPeriodicIaMessages());
  }

  void stopPeriodicIaMessages() {
    executeSyncWithNotification(operation: () => _chatService.stopPeriodicIaMessages());
  }

  @override
  void dispose() {
    // Message service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
