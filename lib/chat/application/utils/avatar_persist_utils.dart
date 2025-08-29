import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';

/// Adds or replaces an avatar in the provider's profile, persists and
/// notifies listeners. Kept in application layer to avoid presentation ->
/// application dependency violations.
Future<void> addAvatarAndPersist(ChatProvider chatProvider, AiImage avatar, {bool replace = false}) async {
  try {
    if (replace) {
      chatProvider.onboardingData = chatProvider.onboardingData.copyWith(avatars: [avatar]);
    } else {
      chatProvider.onboardingData = chatProvider.onboardingData.copyWith(
        avatars: [...(chatProvider.onboardingData.avatars ?? []), avatar],
      );
      try {
        final sysMsg = Message(
          text: 'Se ha añadido un nuevo avatar al historial.',
          sender: MessageSender.system,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
        );
        chatProvider.messages.add(sysMsg);
      } catch (_) {}
    }
    try {
      await chatProvider.saveAll();
    } catch (_) {}
    try {
      chatProvider.notifyListeners();
    } catch (_) {}
  } catch (_) {}
}

/// Removes an AiImage (if non-null) from the provider's onboardingData,
/// persists and notifies listeners. This centralizes the logic used in
/// multiple UI places when the user deletes an image that could be an avatar.
Future<void> removeImageFromProfileAndPersist(ChatProvider chatProvider, AiImage? deleted) async {
  if (deleted == null) return;
  try {
    final current = chatProvider.onboardingData;
    final avatars = List<AiImage>.from(current.avatars ?? []);
    avatars.removeWhere((a) => a.seed == deleted.seed || a.url == deleted.url);
    final updated = current.copyWith(avatars: avatars);
    chatProvider.onboardingData = updated;
    try {
      await chatProvider.saveAll();
    } catch (_) {}
    try {
      chatProvider.notifyListeners();
    } catch (_) {}
  } catch (_) {}
}
