import 'package:ai_chan/onboarding/domain/interfaces/i_onboarding_persistence_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/onboarding_persistence_service_adapter.dart';
import 'package:ai_chan/onboarding/domain/interfaces/i_chat_export_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/chat_export_service_adapter.dart';
import 'package:ai_chan/shared/domain/interfaces/i_shared_logger.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/infrastructure/di/di.dart' as shared_di;
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';

/// Dependency injection container for onboarding bounded context
class OnboardingDI {
  /// Onboarding Persistence Service Factory
  static IOnboardingPersistenceService getOnboardingPersistenceService() =>
      OnboardingPersistenceServiceAdapter();

  /// Chat Export Service Factory - using shared repository
  static IChatExportService getChatExportService() =>
      ChatExportServiceAdapter(shared_di.getSharedChatRepository());

  /// Shared Logger Factory
  static ISharedLogger getSharedLogger() => SharedLoggerAdapter();

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
      logger: getSharedLogger(),
    );
  }
}
