import 'package:ai_chan/onboarding/domain/models/onboarding_form_result.dart';

/// Puerto (Port) para el repositorio de perfil de usuario
/// Define el contrato para persistir y gestionar perfiles durante onboarding
abstract interface class IProfileRepository {
  /// Guarda el resultado del formulario de onboarding
  Future<void> saveOnboardingResult(final OnboardingFormResult result);

  /// Recupera el resultado del onboarding actual
  Future<OnboardingFormResult?> getCurrentOnboardingResult();

  /// Actualiza campos específicos del onboarding
  Future<void> updateOnboardingFields(final Map<String, dynamic> updates);

  /// Verifica si el onboarding está completo
  Future<bool> isOnboardingComplete();

  /// Marca el onboarding como completo
  Future<void> markOnboardingComplete();

  /// Limpia el perfil (reset)
  Future<void> clearProfile();
}
