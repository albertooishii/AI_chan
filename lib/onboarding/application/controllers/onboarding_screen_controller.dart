import 'package:flutter/material.dart';
import 'package:ai_chan/onboarding/application/controllers/onboarding_lifecycle_controller.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/core/models.dart';

/// Application Controller for Onboarding Screen
/// Orchestrates business logic for the onboarding interface
/// Following Clean Architecture principles
class OnboardingScreenController extends ChangeNotifier {
  OnboardingScreenController({
    required final OnboardingLifecycleController onboardingLifecycle,
    final FormOnboardingController? formController,
    final BiographyGenerationUseCase? biographyUseCase,
  }) : _lifecycleController = onboardingLifecycle,
       _formController = formController,
       _biographyUseCase = biographyUseCase ?? BiographyGenerationUseCase();
  final OnboardingLifecycleController _lifecycleController;
  final FormOnboardingController? _formController;
  final BiographyGenerationUseCase _biographyUseCase;

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

  // Onboarding Flow Control
  Future<void> startOnboarding() async {
    await _executeWithLoadingState(
      () async => setCurrentStep(OnboardingStep.biography),
      errorPrefix: 'Error starting onboarding',
    );
  }

  Future<void> nextStep() async {
    await _executeWithLoadingState(() async {
      switch (_currentStep) {
        case OnboardingStep.biography:
          setCurrentStep(OnboardingStep.appearance);
          break;
        case OnboardingStep.appearance:
          setCurrentStep(OnboardingStep.avatar);
          break;
        case OnboardingStep.avatar:
          setCurrentStep(OnboardingStep.complete);
          break;
        case OnboardingStep.complete:
          // Onboarding finished
          break;
      }
    }, errorPrefix: 'Error proceeding to next step');
  }

  Future<void> previousStep() async {
    // Previous step doesn't need loading state, just error handling
    try {
      clearError();

      switch (_currentStep) {
        case OnboardingStep.biography:
          // Already at first step
          break;
        case OnboardingStep.appearance:
          setCurrentStep(OnboardingStep.biography);
          break;
        case OnboardingStep.avatar:
          setCurrentStep(OnboardingStep.appearance);
          break;
        case OnboardingStep.complete:
          setCurrentStep(OnboardingStep.avatar);
          break;
      }
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
    final void Function(BiographyGenerationStep)? onProgress,
  }) async {
    await _executeWithLoadingState(() async {
      // Use the BiographyGenerationUseCase for clean separation
      await _biographyUseCase.generateCompleteBiography(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
        onProgress: onProgress,
      );
    }, errorPrefix: 'Error generating biography');
  }

  Future<void> suggestMeetStory(final BuildContext context) async {
    await _executeWithLoadingState(() async {
      if (_formController != null) {
        await _formController.suggestStory(context);
      }
    }, errorPrefix: 'Error generating story');
  }

  Future<void> pickBirthDate(final BuildContext context) async {
    try {
      clearError();
      // Show date picker here and delegate resulting date into the form controller
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
            dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
          ),
          child: child!,
        ),
      );
      if (picked != null && _formController != null) {
        _formController.setUserBirthdate(picked);
      }
    } on Exception catch (e) {
      setError('Error picking birth date: $e');
    }
  }

  // Form Integration
  bool get hasFormController => _formController != null;

  Future<bool> processFormData({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    if (_formController == null) return false;

    try {
      return await _executeWithLoadingState<bool>(() async {
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
          return true;
        } else {
          setError('Form processing failed');
          return false;
        }
      }, errorPrefix: 'Error processing form');
    } on Exception {
      return false;
    }
  }

  // Import/Export functionality
  Future<bool> importFromJson() async {
    if (_formController == null) return false;

    try {
      return await _executeWithLoadingState<bool>(
        () async => await _formController.importFromJson(),
        errorPrefix: 'Error importing JSON',
      );
    } on Exception {
      return false;
    }
  }

  Future<bool> restoreFromLocalBackup() async {
    if (_formController == null) return false;

    try {
      return await _executeWithLoadingState<bool>(
        () async => await _formController.restoreFromLocalBackup(),
        errorPrefix: 'Error restoring backup',
      );
    } on Exception {
      return false;
    }
  }

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

  // Use case integration methods
  Future<bool> hasCompleteBiography() async {
    try {
      return await _biographyUseCase.hasCompleteBiography();
    } on Exception catch (e) {
      setError('Error checking biography: $e');
      return false;
    }
  }

  Future<AiChanProfile?> loadExistingBiography() async {
    try {
      return await _biographyUseCase.loadExistingBiography();
    } on Exception catch (e) {
      setError('Error loading biography: $e');
      return null;
    }
  }

  Future<void> clearSavedBiography() async {
    try {
      await _biographyUseCase.clearSavedBiography();
      // Also reset provider state
      _lifecycleController.reset();
    } on Exception catch (e) {
      setError('Error clearing biography: $e');
    }
  }
}

/// Onboarding Steps Enumeration
enum OnboardingStep { biography, appearance, avatar, complete }
