import 'package:flutter/material.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

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
class ChatGoogleController extends ChangeNotifier {
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
    try {
      await _chatService.updateGoogleAccountInfo(
        email: email,
        avatarUrl: avatarUrl,
        name: name,
        linked: linked,
        triggerAutoBackup: triggerAutoBackup,
      );
    } on Exception catch (e) {
      debugPrint('Error in updateGoogleAccountInfo: $e');
      rethrow;
    }
  }

  /// Unlink Google account and clear credentials
  Future<void> clearGoogleAccountInfo() async {
    try {
      await _chatService.clearGoogleAccountInfo();
    } on Exception catch (e) {
      debugPrint('Error in clearGoogleAccountInfo: $e');
      rethrow;
    }
  }

  /// Set Google linked status (UI state)
  void setGoogleLinked(final bool linked) {
    try {
      _chatService.setGoogleLinked(linked);
    } on Exception catch (e) {
      debugPrint('Error in setGoogleLinked: $e');
    }
  }

  /// Diagnose Google account state for debugging
  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    try {
      return await _chatService.diagnoseGoogleState();
    } on Exception catch (e) {
      debugPrint('Error in diagnoseGoogleState: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Google service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
