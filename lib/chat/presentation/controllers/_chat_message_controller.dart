import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

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
class ChatMessageController extends ChangeNotifier {
  ChatMessageController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Message state getters
  bool get isTyping => _chatService.isTyping;
  bool get isSendingImage => _chatService.isSendingImage;

  /// User typing indicator
  void onUserTyping(final String text) {
    try {
      _chatService.onUserTyping(text);
    } on Exception catch (e) {
      // Error handling can be added here if needed
      debugPrint('Error in onUserTyping: $e');
    }
  }

  /// Typing indicator
  void setTyping(final bool typing) {
    try {
      _chatService.isTyping = typing;
      notifyListeners(); // Notificar cambios en el estado de escritura
    } on Exception catch (e) {
      debugPrint('Error in setTyping: $e');
    }
  }

  /// Schedule sending a message (legacy compatibility)
  void scheduleSendMessage(
    final String text, {
    final String? model,
    final dynamic image,
    final String? imageMimeType,
  }) {
    try {
      _chatService.scheduleSendMessage(
        text,
        model: model,
        image: image,
        imageMimeType: imageMimeType,
      );
      notifyListeners(); // Notificar que se programó un mensaje
    } on Exception catch (e) {
      debugPrint('Error in scheduleSendMessage: $e');
    }
  }

  /// Add user image message
  void addUserImageMessage(final Message msg) {
    try {
      _chatService.addUserImageMessage(msg);
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in addUserImageMessage: $e');
    }
  }

  /// Add assistant message
  Future<void> addAssistantMessage(
    final String text, {
    final bool isAudio = false,
  }) async {
    try {
      await _chatService.addAssistantMessage(text, isAudio: isAudio);
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in addAssistantMessage: $e');
      rethrow; // Re-throw for UI handling
    }
  }

  /// Add user message
  Future<void> addUserMessage(final Message message) async {
    try {
      await _chatService.addUserMessage(message);
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in addUserMessage: $e');
      rethrow; // Re-throw for UI handling
    }
  }

  /// Retry last failed message
  Future<void> retryLastFailedMessage({final String? model}) async {
    try {
      await _chatService
          .retryLastFailedMessage(); // Model selection is now automatic
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in retryLastFailedMessage: $e');
      rethrow; // Re-throw for UI handling
    }
  }

  /// Control de mensajes periódicos de IA
  void startPeriodicIaMessages() {
    try {
      _chatService.startPeriodicIaMessages();
      notifyListeners(); // Notificar cambios en el estado de mensajes periódicos
    } on Exception catch (e) {
      debugPrint('Error in startPeriodicIaMessages: $e');
    }
  }

  void stopPeriodicIaMessages() {
    try {
      _chatService.stopPeriodicIaMessages();
      notifyListeners(); // Notificar cambios en el estado de mensajes periódicos
    } on Exception catch (e) {
      debugPrint('Error in stopPeriodicIaMessages: $e');
    }
  }

  @override
  void dispose() {
    // Message service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
