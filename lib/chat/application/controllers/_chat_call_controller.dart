import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

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
/// - UI State Management: Via mixin pattern
class ChatCallController extends ChangeNotifier with UIStateManagementMixin {
  ChatCallController({required final ChatApplicationService chatService}) : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Local UI state for calls
  bool _isCalling = false;

  // Call state getters
  bool get isCalling => _isCalling;
  bool get hasPendingIncomingCall => _chatService.hasPendingIncomingCall;
  int get queuedCount => _chatService.queuedCount;

  /// Set calling state (UI only)
  void setCalling(final bool calling) {
    executeSyncWithNotification(operation: () => _isCalling = calling);
  }

  /// Clear pending incoming call
  void clearPendingIncomingCall() {
    executeSyncWithNotification(operation: () => _chatService.clearPendingIncomingCall());
  }

  /// Replace incoming call placeholder with actual call summary
  void replaceIncomingCallPlaceholder({
    required final int index,
    required final VoiceCallSummary summary,
    required final String summaryText,
  }) {
    executeSyncWithNotification(
      operation: () =>
          _chatService.replaceIncomingCallPlaceholder(index: index, summary: summary, summaryText: summaryText),
    );
  }

  /// Reject incoming call placeholder
  void rejectIncomingCallPlaceholder({required final int index, required final String rejectionText}) {
    executeSyncWithNotification(
      operation: () => _chatService.rejectIncomingCallPlaceholder(index: index, rejectionText: rejectionText),
    );
  }

  /// Update or add call status message
  Future<void> updateOrAddCallStatusMessage({
    required final String status,
    final String? metadata,
    final CallStatus? callStatus,
    final bool incoming = false,
    final int? placeholderIndex,
  }) async {
    await delegate(
      serviceCall: () => _chatService.updateOrAddCallStatusMessage(
        status: status,
        metadata: metadata,
        callStatus: callStatus,
        incoming: incoming,
        placeholderIndex: placeholderIndex,
      ),
      errorMessage: 'Error al actualizar estado de llamada',
    );
  }

  /// Force flush queued messages
  Future<void> flushQueuedMessages() async {
    await delegate(
      serviceCall: () => _chatService.flushQueuedMessages(),
      errorMessage: 'Error al enviar mensajes en cola',
    );
  }

  @override
  void dispose() {
    // Call service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
