import 'package:ai_chan/onboarding/domain/interfaces/i_onboarding_persistence_service.dart';
import 'package:ai_chan/shared/infrastructure/utils/prefs_utils.dart';

/// Infrastructure implementation for onboarding persistence operations.
/// Adapts PrefsUtils to domain interface contract.
class OnboardingPersistenceServiceAdapter
    implements IOnboardingPersistenceService {
  @override
  Future<String?> getOnboardingData() async {
    return await PrefsUtils.getOnboardingData();
  }

  @override
  Future<void> removeOnboardingData() async {
    return await PrefsUtils.removeOnboardingData();
  }

  @override
  Future<void> removeChatHistory() async {
    return await PrefsUtils.removeChatHistory();
  }
}
