import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/onboarding/presentation/interfaces/i_form_onboarding_controller.dart';

/// Form Onboarding Controller - Compact form management
class FormOnboardingController extends ChangeNotifier
    implements IFormOnboardingController {
  FormOnboardingController();

  // DDD Application Service for business logic delegation
  final _formService = FormOnboardingApplicationService();

  // Core state
  bool _isLoading = false;
  String? _errorMessage;
  ChatExport? _importedData;

  // Form controllers - centralized management
  late final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final userNameController = TextEditingController();
  final aiNameController = TextEditingController();
  final meetStoryController = TextEditingController();
  final birthDateController = TextEditingController();
  @override
  DateTime? userBirthdate;
  @override
  @override
  String? userCountryCode, aiCountryCode;

  // Getters
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
  @override
  ChatExport? get importedData => _importedData;
  bool get hasImportedData => _importedData != null;
  bool get isFormValid => formKey.currentState?.validate() ?? false;

  /// Initialize form with default values
  void initializeForm() {
    _setLoading(false);
    _clearError();
    meetStoryController.text = 'AUTO_GENERATE_STORY';
    notifyListeners();
  }

  /// Validate current form state
  bool validateForm() {
    final isValid = formKey.currentState?.validate() ?? false;
    if (!isValid) _setError('Please check the form for errors');
    return isValid;
  }

  /// Save form data to profile - delegated to Application Service
  Future<OnboardingFormResult> saveFormData() async {
    return _executeOperation(() async {
      // Delegate to Application Service for processing
      final result = await _formService.processOnboardingData(
        userName: userNameController.text,
        aiName: aiNameController.text,
        meetStory: meetStoryController.text.isNotEmpty
            ? meetStoryController.text
            : 'AUTO_GENERATE_STORY',
        userBirthdate: userBirthdate!,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );

      // Simple logging without LogUtils dependency
      if (result.success) {
        debugPrint('Form saved: ${result.userName}');
      }

      return result;
    });
  }

  /// Import data from JSON - delegated to Application Service
  Future<void> importFromJson(final String jsonData) async {
    await _executeOperationAsync(() async {
      // Delegate to Application Service for import coordination
      final result = await _formService.coordinateDataImport(jsonData);

      if (!result.success) {
        throw Exception(result.error ?? 'Import failed');
      }

      _importedData = result.importedData;

      // Pre-fill form with imported data
      if (result.formPreset != null) {
        final preset = result.formPreset!;
        userNameController.text = preset.userName;
        aiNameController.text = preset.aiName;
        meetStoryController.text = preset.meetStory;

        userBirthdate = preset.userBirthdate;
        if (userBirthdate != null) {
          birthDateController.text = _formService.formatDateForDisplay(
            userBirthdate!,
          );
        }

        userCountryCode = preset.userCountryCode;
        aiCountryCode = preset.aiCountryCode;
      }

      notifyListeners();
    });
  }

  /// Clear imported data
  void clearImportedData() {
    _importedData = null;
    notifyListeners();
  }

  /// Update user birthdate
  void updateUserBirthdate(final DateTime? date) {
    userBirthdate = date;
    _updateBirthDateController();
    notifyListeners();
  }

  /// Update country codes - consolidated
  void updateUserCountry(final String? countryCode) =>
      _updateAndNotify(() => userCountryCode = countryCode);
  void updateAICountry(final String? countryCode) =>
      _updateAndNotify(() => aiCountryCode = countryCode);

  /// Reset form to defaults
  void resetForm() => _updateAndNotify(() {
    userNameController.clear();
    aiNameController.clear();
    meetStoryController.text = 'AUTO_GENERATE_STORY';
    birthDateController.clear();
    userBirthdate = null;
    userCountryCode = null;
    aiCountryCode = null;
    _importedData = null;
    _clearError();
  });

  /// Get form summary - delegated to Application Service
  Map<String, dynamic> getFormSummary() {
    final summary = _formService.generateFormSummary(
      userName: userNameController.text,
      aiName: aiNameController.text,
      meetStory: meetStoryController.text,
      userBirthdate: userBirthdate,
      userCountryCode: userCountryCode,
      aiCountryCode: aiCountryCode,
    );

    return {
      'summary': summary,
      'userName': userNameController.text.trim(),
      'aiName': aiNameController.text.trim(),
      'meetStory': meetStoryController.text.trim(),
      'userBirthdate': userBirthdate?.toIso8601String(),
      'userCountryCode': userCountryCode,
      'aiCountryCode': aiCountryCode,
      'hasImportedData': hasImportedData,
      'isValid': isFormValid,
    };
  }

  /// Check if story suggestion is available (needs at least user name and AI name)
  bool get canSuggestStory {
    return userNameController.text.trim().isNotEmpty &&
        aiNameController.text.trim().isNotEmpty &&
        !isLoading;
  }

  /// Clear current error
  void clearError() {
    _clearError();
    notifyListeners();
  }

  // UI Interface methods - consolidated setters
  void setMeetStory(final String value) =>
      _updateAndNotify(() => meetStoryController.text = value);
  void setUserCountryCode(final String? code) =>
      _updateAndNotify(() => userCountryCode = code);
  void setUserName(final String value) =>
      _updateAndNotify(() => userNameController.text = value);
  void setUserBirthdate(final DateTime? date) => updateUserBirthdate(date);
  void setAiCountryCode(final String? code) =>
      _updateAndNotify(() => aiCountryCode = code);
  void setAiName(final String name) =>
      _updateAndNotify(() => aiNameController.text = name);

  Future<void> suggestStory(final BuildContext context) async {
    await _executeOperationAsync(() async {
      try {
        // Always use OnboardingUtils for story generation with proper prompts
        final story = await OnboardingUtils.generateMeetStoryFromContext(
          userName: userNameController.text.isNotEmpty
              ? userNameController.text
              : 'Usuario',
          aiName: aiNameController.text.isNotEmpty
              ? aiNameController.text
              : 'AI-chan',
          userCountry: userCountryCode,
          aiCountry: aiCountryCode,
          userBirthdate: userBirthdate,
        );

        meetStoryController.text = story;
        notifyListeners();
      } on Exception {
        // If generation fails, show error but don't fallback to hardcoded stories
        _setError('No se pudo generar la historia. Inténtalo de nuevo.');
        notifyListeners();
      }
    });
  }

  bool get isFormCompleteComputed {
    // Delegate to Application Service for completion analysis
    final analysis = _formService.analyzeFormCompletion(
      userName: userNameController.text,
      aiName: aiNameController.text,
      meetStory: meetStoryController.text,
      userBirthdate: userBirthdate,
      userCountryCode: userCountryCode,
      aiCountryCode: aiCountryCode,
      hasImportedData: hasImportedData,
    );

    return analysis.isComplete;
  }

  Future<OnboardingFormResult> processForm({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    // Update internal state with provided values
    userNameController.text = userName;
    aiNameController.text = aiName;
    meetStoryController.text = meetStory;
    this.userCountryCode = userCountryCode;
    this.aiCountryCode = aiCountryCode;

    // Parse birthdate using Application Service
    if (birthDateText.isNotEmpty) {
      final dateResult = _formService.parseDateString(birthDateText);
      if (dateResult.success) {
        userBirthdate = dateResult.parsedDate;
      } else {
        debugPrint('Error parsing birthdate: ${dateResult.error}');
      }
    }

    return await saveFormData();
  }

  // Private helper methods
  T _executeOperation<T>(final T Function() operation) {
    _setLoading(true);
    _clearError();

    try {
      final result = operation();
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _executeOperationAsync(
    final Future<void> Function() operation,
  ) async {
    _setLoading(true);
    _clearError();

    try {
      await operation();
    } on Exception catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _updateBirthDateController() {
    if (userBirthdate != null) {
      // Delegate formatting to Application Service
      birthDateController.text = _formService.formatDateForDisplay(
        userBirthdate!,
      );
    } else {
      birthDateController.clear();
    }
  }

  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Generate biography - interface implementation
  @override
  Future<void> generateBiography() async {
    // Delegate to existing form processing logic
    await saveFormData();
  }

  /// Import chat export data - interface implementation
  @override
  Future<void> importChatExport(final String jsonData) async {
    await importFromJson(jsonData);
  }

  /// Reset error state - interface implementation
  @override
  void resetError() {
    _clearError();
    notifyListeners();
  }

  void _clearError() => _errorMessage = null;

  // Helper method for consolidated updates
  void _updateAndNotify(final void Function() update) {
    update();
    notifyListeners();
  }

  @override
  void dispose() {
    userNameController.dispose();
    aiNameController.dispose();
    meetStoryController.dispose();
    birthDateController.dispose();
    super.dispose();
  }
}
