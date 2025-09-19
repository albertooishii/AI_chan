import 'package:ai_chan/shared/domain/models/index.dart';

/// Shared domain interface for profile persistence operations.
/// Can be used across bounded contexts for profile management.
abstract class IProfilePersistenceService {
  /// Sets onboarding data and persists to storage
  Future<void> setOnboardingDataAndPersist(final AiChanProfile profile);

  /// Sets events and persists to storage
  Future<void> setEventsAndPersist(final List<ChatEvent> events);
}
