import 'package:ai_chan/onboarding/domain/interfaces/i_profile_repository.dart';
import 'package:ai_chan/onboarding/domain/models/onboarding_form_result.dart';
import 'package:flutter/foundation.dart';

/// Implementación en memoria del repositorio de perfil de usuario
/// TODO: Migrar a implementación persistente (SharedPreferences/Hive)
class InMemoryProfileRepository implements IProfileRepository {
  OnboardingFormResult? _currentResult;
  bool _isComplete = false;

  @override
  Future<void> saveOnboardingResult(final OnboardingFormResult result) async {
    _currentResult = result;
    _isComplete = result.success;
    debugPrint(
      '[InMemoryProfileRepository] Onboarding result saved: ${result.success}',
    );
  }

  @override
  Future<OnboardingFormResult?> getCurrentOnboardingResult() async {
    return _currentResult;
  }

  @override
  Future<void> updateOnboardingFields(
    final Map<String, dynamic> updates,
  ) async {
    if (_currentResult == null) {
      debugPrint('[InMemoryProfileRepository] No current result to update');
      return;
    }

    // Crear un nuevo resultado con los campos actualizados
    final updatedResult = OnboardingFormResult(
      success: _currentResult!.success,
      userName: updates['userName'] ?? _currentResult!.userName,
      aiName: updates['aiName'] ?? _currentResult!.aiName,
      userBirthdate: updates['userBirthdate'] ?? _currentResult!.userBirthdate,
      meetStory: updates['meetStory'] ?? _currentResult!.meetStory,
      userCountryCode:
          updates['userCountryCode'] ?? _currentResult!.userCountryCode,
      aiCountryCode: updates['aiCountryCode'] ?? _currentResult!.aiCountryCode,
      errorMessage: _currentResult!.errorMessage,
    );

    _currentResult = updatedResult;
    debugPrint('[InMemoryProfileRepository] Onboarding fields updated');
  }

  @override
  Future<bool> isOnboardingComplete() async {
    return _isComplete;
  }

  @override
  Future<void> markOnboardingComplete() async {
    _isComplete = true;
    debugPrint('[InMemoryProfileRepository] Onboarding marked as complete');
  }

  @override
  Future<void> clearProfile() async {
    _currentResult = null;
    _isComplete = false;
    debugPrint('[InMemoryProfileRepository] Profile cleared');
  }
}
