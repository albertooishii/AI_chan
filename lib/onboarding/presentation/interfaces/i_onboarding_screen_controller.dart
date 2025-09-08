/// 🎯 **Onboarding Screen Controller Interface** - Domain Contract
///
/// Define the contract for onboarding screen operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IOnboardingScreenController {
  // State getters
  bool get isLoading;

  // Core operations
  void dispose();
}
