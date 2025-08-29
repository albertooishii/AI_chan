import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';

/// Helpers to update the provider profile from presentation layer without
/// duplicating persistence logic in many UI files.
Future<void> setOnboardingDataAndPersist(ChatProvider chatProvider, AiChanProfile updated) async {
  try {
    chatProvider.onboardingData = updated;
    try {
      await chatProvider.saveAll();
    } catch (_) {}
    try {
      chatProvider.notifyListeners();
    } catch (_) {}
  } catch (_) {}
}

/// Convenience helper to update only the events list and persist.
Future<void> setEventsAndPersist(ChatProvider chatProvider, List<EventEntry> events) async {
  try {
    final updated = chatProvider.onboardingData.copyWith(events: events);
    await setOnboardingDataAndPersist(chatProvider, updated);
  } catch (_) {}
}
