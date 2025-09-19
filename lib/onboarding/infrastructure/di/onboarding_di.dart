import 'package:ai_chan/onboarding/domain/interfaces/i_onboarding_persistence_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/onboarding_persistence_service_adapter.dart';
// Removed: i_chat_export_service.dart and chat_export_service_adapter.dart - using ISharedChatRepository directly
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared.dart' as shared_di;
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';

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
