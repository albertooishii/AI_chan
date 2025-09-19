import 'package:flutter/material.dart';
import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

/// 📞 **Chat Call Controller** - DDD Specialized Controller
///
/// Handles all call-related functionality for chat:
/// - Call state management (incoming/outgoing)
/// - Call placeholder management
/// - Call status messages
/// - Call queue management
///
/// **DDD Principles:**
/// - Single Responsibility: Only call operations
/// - Delegation: All logic delegated to ChatApplicationService
class ChatCallController extends ChangeNotifier {
  ChatCallController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Local UI state for calls
  bool _isCalling = false;

  // Call state getters
  bool get isCalling => _isCalling;
  bool get hasPendingIncomingCall => _chatService.hasPendingIncomingCall;
  int get queuedCount => _chatService.queuedCount;

  /// Set calling state (UI only)
  void setCalling(final bool calling) {
    try {
      _isCalling = calling;
      notifyListeners(); // Notificar cambios en el estado de llamada
    } on Exception catch (e) {
      debugPrint('Error in setCalling: $e');
    }
  }

  /// Clear pending incoming call
  void clearPendingIncomingCall() {
    try {
      _chatService.clearPendingIncomingCall();
      notifyListeners(); // Notificar cambios en llamadas pendientes
    } on Exception catch (e) {
      debugPrint('Error in clearPendingIncomingCall: $e');
    }
  }

  /// Replace incoming call placeholder with actual call summary
  void replaceIncomingCallPlaceholder({
    required final int index,
    required final VoiceCallSummary summary,
    required final String summaryText,
  }) {
    try {
      _chatService.replaceIncomingCallPlaceholder(
        index: index,
        summary: summary,
        summaryText: summaryText,
      );
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in replaceIncomingCallPlaceholder: $e');
    }
  }

  /// Reject incoming call placeholder
  void rejectIncomingCallPlaceholder({
    required final int index,
    required final String rejectionText,
  }) {
    try {
      _chatService.rejectIncomingCallPlaceholder(
        index: index,
        rejectionText: rejectionText,
      );
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in rejectIncomingCallPlaceholder: $e');
    }
  }

  /// Update or add call status message
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
      notifyListeners(); // Notificar cambios en los mensajes
    } on Exception catch (e) {
      debugPrint('Error in updateOrAddCallStatusMessage: $e');
      rethrow;
    }
  }

  /// Force flush queued messages
  Future<void> flushQueuedMessages() async {
    try {
      await _chatService.flushQueuedMessages();
      notifyListeners(); // Notificar cambios en la cola de mensajes
    } on Exception catch (e) {
      debugPrint('Error in flushQueuedMessages: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Call service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
