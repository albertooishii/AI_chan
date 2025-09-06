class OnboardingFormResult {
  const OnboardingFormResult({
    required this.success,
    this.userName,
    this.aiName,
    this.userBirthdate,
    this.meetStory,
    this.userCountryCode,
    this.aiCountryCode,
    this.errorMessage,
  });

  factory OnboardingFormResult.success({
    required final String userName,
    required final String aiName,
    required final DateTime userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) => OnboardingFormResult(
    success: true,
    userName: userName,
    aiName: aiName,
    userBirthdate: userBirthdate,
    meetStory: meetStory,
    userCountryCode: userCountryCode,
    aiCountryCode: aiCountryCode,
  );

  factory OnboardingFormResult.failure(final String errorMessage) =>
      OnboardingFormResult(success: false, errorMessage: errorMessage);
  final bool success;
  final String? userName;
  final String? aiName;
  final DateTime? userBirthdate;
  final String? meetStory;
  final String? userCountryCode;
  final String? aiCountryCode;
  final String? errorMessage;
}
