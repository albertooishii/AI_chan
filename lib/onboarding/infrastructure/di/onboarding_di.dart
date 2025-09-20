import 'package:ai_chan/onboarding.dart';
// Removed: i_chat_export_service.dart and chat_export_service_adapter.dart - using ISharedChatRepository directly
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared.dart' as shared_di;

/// Dependency injection container for onboarding bounded context
class OnboardingDI {
  /// Onboarding Persistence Service Factory
  static IOnboardingPersistenceService getOnboardingPersistenceService() =>
      OnboardingPersistenceServiceAdapter();

  /// Shared Chat Repository Service Factory - for chat export functionality
  static ISharedChatRepository getChatExportService() =>
      shared_di.getSharedChatRepository();

  /// Profile Service Factory (from shared context)
  static Future<IProfileService> getProfileService() async =>
      await shared_di.getProfileServiceForProvider();

  /// Biography Generation Use Case Factory
  static Future<BiographyGenerationUseCase>
  getBiographyGenerationUseCase() async {
    return BiographyGenerationUseCase(
      profileService: await getProfileService(),
      chatExportService: getChatExportService(),
      onboardingPersistenceService: getOnboardingPersistenceService(),
    );
  }
}
