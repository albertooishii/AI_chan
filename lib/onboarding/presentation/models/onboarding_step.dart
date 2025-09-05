/// Enumeración de los pasos del onboarding conversacional
/// Exactamente igual al original para mantener compatibilidad
enum OnboardingStep {
  awakening, // Primer despertar de AI-chan
  askingName, // Preguntando el nombre del usuario
  askingCountry, // Preguntando el país del usuario
  askingBirthdate, // Preguntando la fecha de nacimiento
  askingAiCountry, // Preguntando el país de la IA
  askingAiName, // Preguntando el nombre para la IA
  askingMeetStory, // Preguntando cómo se conocieron
  finalMessage, // Mensaje final antes de completar
  completion, // Onboarding completado
}

/// Extension para obtener texto descriptivo de cada paso
extension OnboardingStepExtension on OnboardingStep {
  String get description {
    switch (this) {
      case OnboardingStep.awakening:
        return 'Despertando...';
      case OnboardingStep.askingName:
        return 'Preguntando nombre';
      case OnboardingStep.askingCountry:
        return 'Preguntando país';
      case OnboardingStep.askingBirthdate:
        return 'Preguntando fecha de nacimiento';
      case OnboardingStep.askingAiName:
        return 'Preguntando nombre de IA';
      case OnboardingStep.askingAiCountry:
        return 'Preguntando país de IA';
      case OnboardingStep.askingMeetStory:
        return 'Preguntando historia';
      case OnboardingStep.finalMessage:
        return 'Mensaje final';
      case OnboardingStep.completion:
        return 'Completado';
    }
  }

  bool get isCompleted => this == OnboardingStep.completion;
  bool get isAskingUserData => [
    OnboardingStep.askingName,
    OnboardingStep.askingCountry,
    OnboardingStep.askingBirthdate,
  ].contains(this);

  bool get isAskingAiData => [
    OnboardingStep.askingAiCountry,
    OnboardingStep.askingAiName,
  ].contains(this);
}
