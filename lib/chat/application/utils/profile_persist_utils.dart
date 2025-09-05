import 'package:ai_chan/chat/application/controllers/chat_controller.dart';
import 'package:ai_chan/core/models.dart';

/// Helpers to update the chat controller profile from presentation layer without
/// duplicating persistence logic in many UI files.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> setOnboardingDataAndPersist(
  ChatController chatController,
  AiChanProfile updated,
) async {
  try {
    chatController.updateProfile(updated);
    // ChatController automatically handles persistence and notifications
  } catch (_) {
    // Handle errors silently as in original implementation
  }
}

/// Convenience helper to update only the events list and persist.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> setEventsAndPersist(
  ChatController chatController,
  List<EventEntry> events,
) async {
  try {
    final currentProfile = chatController.profile;
    if (currentProfile != null) {
      final updated = currentProfile.copyWith(events: events);
      await setOnboardingDataAndPersist(chatController, updated);
    }
  } catch (_) {
    // Handle errors silently as in original implementation
  }
}
