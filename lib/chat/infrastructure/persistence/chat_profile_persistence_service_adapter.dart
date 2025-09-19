import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_profile_persistence_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_logger.dart';
import 'package:ai_chan/shared/domain/models/index.dart';

/// Infrastructure adapter implementing chat profile persistence using ChatController.
/// Bridges domain interface with application layer chat controller functionality.
class ChatProfilePersistenceServiceAdapter
    implements IChatProfilePersistenceService {
  const ChatProfilePersistenceServiceAdapter(
    this._chatController,
    this._logger,
  );
  final IChatController _chatController;
  final IChatLogger _logger;

  @override
  Future<void> setOnboardingDataAndPersist(final AiChanProfile profile) async {
    try {
      // Update in-memory profile
      _chatController.dataController.updateProfile(profile);

      // Ensure the controller persists the new profile to storage immediately
      try {
        await _chatController.saveState();
        _logger.debug(
          'profile_persist_service: persisted onboarding data for aiName=${profile.aiName}',
        );
      } on Exception catch (e, st) {
        _logger.error(
          'profile_persist_service: failed to persist onboarding data for aiName=${profile.aiName} error=$e',
          tag: 'PERSIST',
          error: e,
        );
        _logger.error(st.toString(), tag: 'PERSIST');
        rethrow;
      }
    } on Exception catch (e, st) {
      _logger.error(
        'profile_persist_service: unexpected error setting onboarding data: $e',
        tag: 'PERSIST',
        error: e,
      );
      _logger.error(st.toString(), tag: 'PERSIST');
      rethrow;
    }
  }

  @override
  Future<void> setEventsAndPersist(final List<ChatEvent> events) async {
    try {
      final currentProfile = getCurrentProfile();
      if (currentProfile != null) {
        final updated = currentProfile.copyWith();
        await setOnboardingDataAndPersist(updated);
      }
    } on Exception catch (_) {
      // Handle errors silently as in original implementation
    }
  }

  @override
  AiChanProfile? getCurrentProfile() {
    return _chatController.profile;
  }
}
