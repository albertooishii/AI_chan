import 'onboarding_step.dart';

/// Estado del onboarding conversacional
class OnboardingState {
  final OnboardingStep currentStep;
  final Map<String, dynamic> collectedData;
  final String? pendingValidationValue;
  final bool isWaitingForConfirmation;
  final String? tempSuggestedStory;
  final int operationId;

  const OnboardingState({
    required this.currentStep,
    required this.collectedData,
    this.pendingValidationValue,
    this.isWaitingForConfirmation = false,
    this.tempSuggestedStory,
    this.operationId = 0,
  });

  OnboardingState copyWith({
    OnboardingStep? currentStep,
    Map<String, dynamic>? collectedData,
    String? pendingValidationValue,
    bool? isWaitingForConfirmation,
    String? tempSuggestedStory,
    int? operationId,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      collectedData: collectedData ?? this.collectedData,
      pendingValidationValue:
          pendingValidationValue ?? this.pendingValidationValue,
      isWaitingForConfirmation:
          isWaitingForConfirmation ?? this.isWaitingForConfirmation,
      tempSuggestedStory: tempSuggestedStory ?? this.tempSuggestedStory,
      operationId: operationId ?? this.operationId,
    );
  }

  /// Extrae datos tipados del estado
  String? get userName => collectedData['userName'] as String?;
  String? get userCountry => collectedData['userCountry'] as String?;
  DateTime? get userBirthday => collectedData['userBirthday'] as DateTime?;
  String? get aiName => collectedData['aiName'] as String?;
  String? get aiCountry => collectedData['aiCountry'] as String?;
  String? get meetStory => collectedData['meetStory'] as String?;
}
