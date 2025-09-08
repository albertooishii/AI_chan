import 'package:ai_chan/core/models.dart';

/// 🎯 **Form Onboarding Controller Interface** - Domain Contract
///
/// Define the contract for form onboarding operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IFormOnboardingController {
  // State getters
  bool get isLoading;
  String? get errorMessage;
  ChatExport? get importedData;

  // Form data getters
  String? get userCountryCode;
  String? get aiCountryCode;
  DateTime? get userBirthdate;

  // Core operations
  Future<void> generateBiography();
  Future<void> importChatExport(final String data);
  void resetError();
  void dispose();
}
