/// Entidad de dominio para los pasos del onboarding conversacional
enum OnboardingStep {
  awakening,
  askingCountry,
  askingBirthday,
  askingAiCountry,
  askingAiName,
  askingMeetStory,
  finalMessage,
  completion,
}

extension OnboardingStepExtensions on OnboardingStep {
  /// Obtiene el nombre del paso para logging y procesamiento
  String get stepName => toString().split('.').last;

  /// Determina si este paso requiere validación
  bool get requiresValidation {
    switch (this) {
      case OnboardingStep.askingCountry:
      case OnboardingStep.askingBirthday:
      case OnboardingStep.askingAiCountry:
      case OnboardingStep.askingAiName:
        return true;
      case OnboardingStep.awakening:
      case OnboardingStep.askingMeetStory:
      case OnboardingStep.finalMessage:
      case OnboardingStep.completion:
        return false;
    }
  }

  /// Obtiene el siguiente paso en la secuencia
  OnboardingStep? get nextStep {
    final values = OnboardingStep.values;
    final currentIndex = values.indexOf(this);
    if (currentIndex < values.length - 1) {
      return values[currentIndex + 1];
    }
    return null;
  }
}
