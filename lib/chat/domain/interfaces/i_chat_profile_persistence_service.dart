import 'package:ai_chan/shared/domain/models/index.dart';

/// Domain interface for profile persistence within chat bounded context.
/// Provides abstraction for profile updates and persistence operations.
abstract class IChatProfilePersistenceService {
  /// Sets onboarding data and ensures it's persisted to storage.
  /// Returns Future that completes when data is durably stored.
  Future<void> setOnboardingDataAndPersist(final AiChanProfile profile);

  /// Updates only the events list and persists the change.
  /// Returns Future that completes when data is durably stored.
  Future<void> setEventsAndPersist(final List<ChatEvent> events);

  /// Gets the current profile if available.
  AiChanProfile? getCurrentProfile();
}
