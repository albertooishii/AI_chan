import 'package:ai_chan/chat/application/controllers/chat_controller.dart';
import 'package:ai_chan/core/models.dart';

/// Adds or replaces an avatar in the controller's profile, persists and
/// notifies listeners. Kept in application layer to avoid presentation ->
/// application dependency violations.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> addAvatarAndPersist(
  final ChatController chatController,
  final AiImage avatar, {
  final bool replace = false,
}) async {
  try {
    final currentProfile = chatController.profile;
    if (currentProfile == null) return;

    AiChanProfile updatedProfile;
    if (replace) {
      updatedProfile = currentProfile.copyWith(avatars: [avatar]);
    } else {
      updatedProfile = currentProfile.copyWith(
        avatars: [...(currentProfile.avatars ?? []), avatar],
      );
      // Note: System message about avatar addition is now handled by ChatController
      // through the domain events system instead of direct message manipulation
    }

    chatController.updateProfile(updatedProfile);
    // ChatController automatically handles persistence and notifications
  } on Exception catch (_) {
    // Handle errors silently as in original implementation
  }
}

/// Removes an AiImage (if non-null) from the controller's profile,
/// persists and notifies listeners. This centralizes the logic used in
/// multiple UI places when the user deletes an image that could be an avatar.
///
/// ✅ DDD MIGRATION: Updated to use ChatController instead of legacy ChatProvider
Future<void> removeImageFromProfileAndPersist(
  final ChatController chatController,
  final AiImage? deleted,
) async {
  if (deleted == null) return;
  try {
    final currentProfile = chatController.profile;
    if (currentProfile == null) return;

    final avatars = List<AiImage>.from(currentProfile.avatars ?? []);
    avatars.removeWhere(
      (final a) => a.seed == deleted.seed || a.url == deleted.url,
    );
    final updated = currentProfile.copyWith(avatars: avatars);

    chatController.updateProfile(updated);
    // ChatController automatically handles persistence and notifications
  } on Exception catch (_) {
    // Handle errors silently as in original implementation
  }
}
