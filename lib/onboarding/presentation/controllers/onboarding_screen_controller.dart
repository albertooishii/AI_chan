import 'package:flutter/material.dart';
import 'package:ai_chan/onboarding.dart';

/// Onboarding Screen Controller - Compact using Application Service pattern
class OnboardingScreenController extends ChangeNotifier {
  OnboardingScreenController({
    final OnboardingApplicationService? applicationService,
  }) : _applicationService =
           applicationService ?? OnboardingApplicationService();

  final OnboardingApplicationService _applicationService;

  // UI State
  bool _isLoading = false;
  String? _errorMessage;
  int _currentStepIndex = 0;
  double _completionProgress = 0.0;

  // Step definitions
  final List<String> _steps = ['biography', 'appearance', 'voice', 'summary'];

  // Getters

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentStepIndex => _currentStepIndex;
  String get currentStep => _steps[_currentStepIndex];
  bool get isNavigationLocked => _isLoading;
  double get completionProgress => _completionProgress;
  bool get canProceedToNext =>
      _currentStepIndex < _steps.length - 1 && !_isLoading;
  bool get canGoBack => _currentStepIndex > 0 && !_isLoading;
  bool get isCompleted => _completionProgress >= 1.0;
  List<String> get allSteps => List.unmodifiable(_steps);

  /// Initialize onboarding
  Future<void> initialize() async {
    await _executeOperation(() async {
      _updateProgress();
    });
  }

  /// Process user input for current step
  Future<void> processUserInput(final String input) async {
    await _executeOperation(() async {
      // Delegate to application service for processing
      _applicationService.addConversationEntry('user_input', input);

      // Update progress based on input processing
      _updateProgress();
    });
  }

  /// Generate content for current step
  Future<void> generateContent() async {
    await _executeOperation(() async {
      _applicationService.addConversationEntry('generate_content', currentStep);
      _updateProgress();
    });
  }

  /// Reset onboarding
  Future<void> resetOnboarding() async {
    await _executeOperation(() async {
      _applicationService.clearConversationHistory();
      _currentStepIndex = 0;
      _completionProgress = 0.0;
    });
  }

  /// Clear current error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get conversation history from application service
  List<Map<String, String>> getConversationHistory() =>
      _applicationService.getConversationHistory();

  // Private helper methods
  Future<void> _executeOperation(
    final Future<void> Function() operation,
  ) async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      await operation();
    } on Exception catch (e) {
      _setError('Operation failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _updateProgress() {
    // Calculate progress based on step completion
    final stepProgress = _currentStepIndex / (_steps.length - 1);
    final historyProgress = _calculateHistoryCompleteness();
    _completionProgress = (stepProgress * 0.7 + historyProgress * 0.3).clamp(
      0.0,
      1.0,
    );
    notifyListeners();
  }

  double _calculateHistoryCompleteness() {
    final history = _applicationService.getConversationHistory();
    if (history.isEmpty) return 0.0;

    // Simple heuristic: more conversation entries = more progress
    final maxExpectedEntries = _steps.length * 3; // Estimate
    return (history.length / maxExpectedEntries).clamp(0.0, 1.0);
  }

  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() => _errorMessage = null;
}
