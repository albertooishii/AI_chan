import 'package:ai_chan/core/models.dart';

/// 🎯 **Onboarding Lifecycle Controller Interface** - Domain Contract
///
/// Define the contract for onboarding lifecycle operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IOnboardingLifecycleController {
  // State getters
  bool get loading;
  AiChanProfile? get generatedBiography;
  bool get biographySaved;
  String? get importError;

  // Core operations
  Future<void> applyChatExport(final ChatExport exported);
  void setImportError(final String? error);
  Future<void> reset();
}
