/// Shared domain interface for onboarding persistence operations.
/// Abstracts onboarding data storage without bounded context dependencies.
abstract interface class IOnboardingPersistenceService {
  /// Gets onboarding data as JSON string
  /// Returns null if no data exists
  Future<String?> getOnboardingData();

  /// Removes all onboarding data from storage
  Future<void> removeOnboardingData();

  /// Removes chat history from storage
  Future<void> removeChatHistory();
}
