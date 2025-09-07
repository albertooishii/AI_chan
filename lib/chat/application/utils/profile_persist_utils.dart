import 'package:ai_chan/chat/application/controllers/chat_controller.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Helpers to update the chat controller profile from presentation layer without
/// duplicating persistence logic in many UI files.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> setOnboardingDataAndPersist(
  final ChatController chatController,
  final AiChanProfile updated,
) async {
  try {
    // Update in-memory profile
    chatController.dataController.updateProfile(updated);
    // Ensure the controller persists the new profile to storage immediately.
    // Use the public saveState API which delegates to the application service
    // persistence layer. Await so callers can be sure data is durable.
    try {
      await chatController.saveState();
      Log.d(
        'profile_persist_utils: persisted onboarding data for aiName=${updated.aiName}',
      );
    } on Exception catch (e, st) {
      Log.e(
        'profile_persist_utils: failed to persist onboarding data for aiName=${updated.aiName} error=$e',
        tag: 'PERSIST',
        error: e,
      );
      Log.e(st.toString(), tag: 'PERSIST');
      rethrow;
    }
  } on Exception catch (e, st) {
    Log.e(
      'profile_persist_utils: unexpected error setting onboarding data: $e',
      tag: 'PERSIST',
      error: e,
    );
    Log.e(st.toString(), tag: 'PERSIST');
    rethrow;
  }
}

/// Convenience helper to update only the events list and persist.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> setEventsAndPersist(
  final ChatController chatController,
  final List<EventEntry> events,
) async {
  try {
    final currentProfile = chatController.profile;
    if (currentProfile != null) {
      final updated = currentProfile.copyWith();
      await setOnboardingDataAndPersist(chatController, updated);
    }
  } on Exception catch (_) {
    // Handle errors silently as in original implementation
  }
}
