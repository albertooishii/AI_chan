import 'package:flutter/material.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

/// 🔗 **Chat Google Controller** - DDD Specialized Controller
///
/// Handles all Google integration functionality for chat:
/// - Google account linking/unlinking
/// - Google Drive backup management
/// - Google account state management
///
/// **DDD Principles:**
/// - Single Responsibility: Only Google operations
/// - Delegation: All logic delegated to ChatApplicationService
/// - UI State Management: Via mixin pattern
class ChatGoogleController extends ChangeNotifier with UIStateManagementMixin {
  ChatGoogleController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Google account state getters (delegated to service)
  bool get googleLinked => _chatService.googleLinked;
  String? get googleEmail => _chatService.googleEmail;
  String? get googleAvatarUrl => _chatService.googleAvatarUrl;
  String? get googleName => _chatService.googleName;

  /// Link Google account with optional auto-backup trigger
  Future<void> updateGoogleAccountInfo({
    final String? email,
    final String? avatarUrl,
    final String? name,
    final bool linked = true,
    final bool triggerAutoBackup = false,
  }) async {
    await delegate(
      serviceCall: () => _chatService.updateGoogleAccountInfo(
        email: email,
        avatarUrl: avatarUrl,
        name: name,
        linked: linked,
        triggerAutoBackup: triggerAutoBackup,
      ),
      errorMessage: 'Error al actualizar cuenta Google',
    );
  }

  /// Unlink Google account and clear credentials
  Future<void> clearGoogleAccountInfo() async {
    await delegate(
      serviceCall: () => _chatService.clearGoogleAccountInfo(),
      errorMessage: 'Error al limpiar cuenta Google',
    );
  }

  /// Set Google linked status (UI state)
  void setGoogleLinked(final bool linked) {
    executeSyncWithNotification(
      operation: () => _chatService.setGoogleLinked(linked),
    );
  }

  /// Diagnose Google account state for debugging
  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    return await _chatService.diagnoseGoogleState();
  }

  @override
  void dispose() {
    // Google service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
