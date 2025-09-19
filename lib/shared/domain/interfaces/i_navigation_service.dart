abstract class INavigationService {
  /// Navigate to voice screen
  Future<void> navigateToVoice();

  /// Navigate to chat screen
  Future<void> navigateToChat();

  /// Navigate to onboarding screen
  Future<void> navigateToOnboarding();

  /// Navigate back
  void goBack();

  /// Check if can go back
  bool canGoBack();
}
