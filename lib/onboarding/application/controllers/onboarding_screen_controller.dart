import 'package:flutter/material.dart';
import 'package:ai_chan/onboarding/domain/domain.dart';
import 'package:ai_chan/onboarding/application/controllers/onboarding_lifecycle_controller.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/onboarding/application/services/onboarding_application_service.dart';
import 'package:ai_chan/core/models.dart';

/// 🎯 **Onboarding Screen Controller - DDD Refactored**
/// Delegated to OnboardingApplicationService for complexity reduction (317→<200 lines)
class OnboardingScreenController extends ChangeNotifier {
  OnboardingScreenController({
    required final OnboardingLifecycleController onboardingLifecycle,
    final FormOnboardingController? formController,
    final BiographyGenerationUseCase? biographyUseCase,
    final OnboardingApplicationService? applicationService,
  }) : _lifecycleController = onboardingLifecycle,
       _formController = formController,
       _biographyUseCase = biographyUseCase ?? BiographyGenerationUseCase(),
       _applicationService =
           applicationService ?? OnboardingApplicationService();

  final OnboardingLifecycleController _lifecycleController;
  final FormOnboardingController? _formController;
  final BiographyGenerationUseCase _biographyUseCase;
  final OnboardingApplicationService _applicationService;

  // UI State
  bool _isLoading = false;
  String? _errorMessage;
  OnboardingStep _currentStep = OnboardingStep.biography;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  OnboardingStep get currentStep => _currentStep;
  OnboardingLifecycleController get onboardingLifecycle => _lifecycleController;
  FormOnboardingController? get formController => _formController;

  // UI State Management
  void setLoading(final bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void setError(final String? error) {
    if (_errorMessage != error) {
      _errorMessage = error;
      notifyListeners();
    }
  }

  void clearError() => setError(null);

  /// Common helper for operations that need loading state and error handling
  Future<T> _executeWithLoadingState<T>(
    final Future<T> Function() operation, {
    final String? errorPrefix,
  }) async {
    try {
      setLoading(true);
      clearError();
      return await operation();
    } on Exception catch (e) {
      final message = errorPrefix != null ? '$errorPrefix: $e' : e.toString();
      setError(message);
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  void setCurrentStep(final OnboardingStep step) {
    if (_currentStep != step) {
      _currentStep = step;
      notifyListeners();
    }
  }

  // Flow Control
  Future<void> startOnboarding() => _executeWithLoadingState(
    () async => setCurrentStep(OnboardingStep.biography),
    errorPrefix: 'Error starting onboarding',
  );

  Future<void> nextStep() => _executeWithLoadingState(() async {
    final stepMap = {
      OnboardingStep.biography: OnboardingStep.appearance,
      OnboardingStep.appearance: OnboardingStep.avatar,
      OnboardingStep.avatar: OnboardingStep.complete,
      OnboardingStep.complete: OnboardingStep.complete,
    };
    setCurrentStep(stepMap[_currentStep] ?? OnboardingStep.complete);
  }, errorPrefix: 'Error proceeding to next step');

  Future<void> previousStep() async {
    try {
      clearError();
      final stepMap = {
        OnboardingStep.biography: OnboardingStep.biography,
        OnboardingStep.appearance: OnboardingStep.biography,
        OnboardingStep.avatar: OnboardingStep.appearance,
        OnboardingStep.complete: OnboardingStep.avatar,
      };
      setCurrentStep(stepMap[_currentStep] ?? OnboardingStep.biography);
    } on Exception catch (e) {
      setError('Error going to previous step: $e');
    }
  }

  // Profile Generation
  Future<void> generateBiography({
    required final BuildContext context,
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    await _executeWithLoadingState(() async {
      await _biographyUseCase.generateCompleteBiography(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
    }, errorPrefix: 'Error generating biography');
  }

  Future<void> suggestMeetStory(final BuildContext context) =>
      _executeWithLoadingState(() async {
        _formController?.suggestStory(context);
      }, errorPrefix: 'Error generating story');

  Future<void> pickBirthDate(final BuildContext context) async {
    try {
      clearError();
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(now.year - 25),
        firstDate: DateTime(1950),
        lastDate: now,
        locale: const Locale('es'),
        builder: (final context, final child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.pinkAccent,
              surface: Colors.black,
              onSurface: Colors.pinkAccent,
            ),
          ),
          child: child!,
        ),
      );
      if (picked != null) _formController?.setUserBirthdate(picked);
    } on Exception catch (e) {
      setError('Error picking birth date: $e');
    }
  }

  // Form Integration
  bool get hasFormController => _formController != null;

  // Form Processing
  Future<OnboardingFormResult> processFormData({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    if (_formController == null) {
      return OnboardingFormResult.failure('Form controller not available');
    }

    try {
      return await _executeWithLoadingState<OnboardingFormResult>(() async {
        final result = await _formController.processForm(
          userName: userName,
          aiName: aiName,
          birthDateText: birthDateText,
          meetStory: meetStory,
          userCountryCode: userCountryCode,
          aiCountryCode: aiCountryCode,
        );

        if (result.success) {
          await nextStep();
        } else {
          setError('Form processing failed');
        }
        return result;
      }, errorPrefix: 'Error processing form');
    } on Exception {
      return OnboardingFormResult.failure(
        'Unexpected error during form processing',
      );
    }
  }

  // Import/Export delegation
  Future<bool> importFromJson() async => _formController != null
      ? _executeWithLoadingState<bool>(
          () => _formController.importFromJson(),
          errorPrefix: 'Import error',
        )
      : false;

  Future<bool> restoreFromLocalBackup() async => _formController != null
      ? _executeWithLoadingState<bool>(
          () => _formController.restoreFromLocalBackup(),
          errorPrefix: 'Restore error',
        )
      : false;

  // Helper methods
  bool get canGoNext {
    switch (_currentStep) {
      case OnboardingStep.biography:
        return _lifecycleController.biographySaved;
      case OnboardingStep.appearance:
        return _lifecycleController.generatedBiography?.appearance.isNotEmpty ==
            true;
      case OnboardingStep.avatar:
        return _lifecycleController.generatedBiography?.avatars?.isNotEmpty ==
            true;
      case OnboardingStep.complete:
        return false;
    }
  }

  bool get canGoPrevious => _currentStep != OnboardingStep.biography;

  double get progress {
    switch (_currentStep) {
      case OnboardingStep.biography:
        return 0.25;
      case OnboardingStep.appearance:
        return 0.5;
      case OnboardingStep.avatar:
        return 0.75;
      case OnboardingStep.complete:
        return 1.0;
    }
  }

  // Application Service Delegation
  Future<bool> hasCompleteBiography() async {
    try {
      // ✅ DDD: Delegar al Application Service
      final memory = _applicationService.getMemoryState();
      return _applicationService.isOnboardingComplete(memory);
    } on Exception catch (e) {
      setError('Error checking biography: $e');
      return false;
    }
  }

  // Biography Loading
  Future<AiChanProfile?> loadExistingBiography() async {
    try {
      final memoryState = _applicationService.getMemoryState();
      // Check if memory has sufficient data to load biography
      if (memoryState.isComplete() ||
          (memoryState.userName?.isNotEmpty == true)) {
        return await _biographyUseCase.loadExistingBiography();
      }
      return null;
    } on Exception catch (e) {
      setError('Error loading biography: $e');
      return null;
    }
  }

  Future<void> clearSavedBiography() async {
    try {
      // ✅ DDD: Reset via Application Service
      await _applicationService.resetOnboarding();
      _lifecycleController.reset();
    } on Exception catch (e) {
      setError('Error clearing biography: $e');
    }
  }
}

/// Onboarding Steps Enumeration
enum OnboardingStep { biography, appearance, avatar, complete }
