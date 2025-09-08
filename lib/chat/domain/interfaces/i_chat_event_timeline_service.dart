/// Domain interface for event timeline operations within chat bounded context
/// Abstracts event detection and scheduling functionality.
abstract interface class IChatEventTimelineService {
  /// Detect events from AI response and save them with scheduling
  Future<dynamic> detectAndSaveEventAndSchedule({
    required final String text,
    required final String textResponse,
    required final dynamic onboardingData,
    required final Future<void> Function() saveAll,
  });
}
