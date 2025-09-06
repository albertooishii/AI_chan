import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/application/use_cases/form_onboarding_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/import_export_onboarding_use_case.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';

/// Controller para el onboarding por formulario
/// Coordina la UI con los casos de uso, manteniendo la separación de responsabilidades
class FormOnboardingController extends ChangeNotifier {
  FormOnboardingController({
    final FormOnboardingUseCase? formUseCase,
    final ImportExportOnboardingUseCase? importExportUseCase,
  }) : _formUseCase = formUseCase ?? FormOnboardingUseCase(),
       _importExportUseCase =
           importExportUseCase ?? ImportExportOnboardingUseCase();
  final FormOnboardingUseCase _formUseCase;
  final ImportExportOnboardingUseCase _importExportUseCase;

  // Estado del controller
  bool _isLoading = false;
  String? _errorMessage;
  ChatExport? _importedData;

  // Form fields owned by the controller (migrating responsibility from provider)
  // Keep a form key so presentation code can reference the same key as before
  late final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final userNameController = TextEditingController();
  final aiNameController = TextEditingController();
  final meetStoryController = TextEditingController();
  final birthDateController = TextEditingController();
  DateTime? userBirthdate;
  String? userCountryCode;
  String? aiCountryCode;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ChatExport? get importedData => _importedData;
  bool get hasError => _errorMessage != null;

  // Convenience getter that mirrors old provider logic
  bool get isFormCompleteComputed => isFormComplete(
    userName: userNameController.text,
    aiName: aiNameController.text,
    birthDateText: birthDateController.text,
    meetStory: meetStoryController.text,
  );

  /// Valida si el formulario está completo
  bool isFormComplete({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
  }) {
    return _formUseCase.isFormComplete(
      userName: userName,
      aiName: aiName,
      birthDateText: birthDateText,
      meetStory: meetStory,
    );
  }

  /// Procesa los datos del formulario
  Future<OnboardingFormResult> processForm({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      Log.d(
        '🎯 Procesando formulario de onboarding',
        tag: 'FORM_ONBOARDING_CTRL',
      );

      final result = await _formUseCase.processFormData(
        userName: userName,
        aiName: aiName,
        birthDateText: birthDateText,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );

      if (!result.success) {
        _setError(result.errorMessage);
      }

      return result;
    } catch (e) {
      Log.e('Error procesando formulario: $e', tag: 'FORM_ONBOARDING_CTRL');
      _setError('Error inesperado procesando el formulario: $e');
      return OnboardingFormResult(
        success: false,
        errors: ['Error inesperado: $e'],
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Importa datos desde JSON
  Future<bool> importFromJson() async {
    return await _handleImportOperation(
      () => _importExportUseCase.importFromJson(),
      '📤 Iniciando importación JSON',
      '✅ Importación JSON exitosa',
      '🚫 Importación JSON cancelada',
      'Error durante importación JSON',
    );
  }

  /// Restaura desde un backup local
  Future<bool> restoreFromLocalBackup() async {
    return await _handleImportOperation(
      () => _importExportUseCase.restoreFromLocalBackup(),
      '📥 Iniciando restauración de backup',
      '✅ Restauración de backup exitosa',
      '🚫 Restauración de backup cancelada',
      'Error durante restauración',
    );
  }

  /// Maneja operaciones de importación/restauración de forma genérica
  Future<bool> _handleImportOperation(
    final Future<ImportExportResult> Function() operation,
    final String startMessage,
    final String successMessage,
    final String cancelMessage,
    final String errorPrefix,
  ) async {
    _setLoading(true);
    _clearError();

    try {
      Log.d(startMessage, tag: 'FORM_ONBOARDING_CTRL');

      final result = await operation();

      if (result.isSuccess) {
        _importedData = result.data;
        Log.d(successMessage, tag: 'FORM_ONBOARDING_CTRL');
        return true;
      } else if (result.wasCancelled) {
        Log.d(cancelMessage, tag: 'FORM_ONBOARDING_CTRL');
        return false;
      } else {
        _setError(result.error ?? 'Error desconocido');
        return false;
      }
    } catch (e) {
      Log.e('$errorPrefix: $e', tag: 'FORM_ONBOARDING_CTRL');
      _setError('Error inesperado: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Limpia los datos importados
  void clearImportedData() {
    _importedData = null;
    _clearError();
    notifyListeners();
  }

  // --- Form state setters (migrated from provider) ---
  void setUserName(final String value) {
    userNameController.text = value;
    notifyListeners();
  }

  void setAiName(final String value) {
    aiNameController.text = value;
    notifyListeners();
  }

  void setUserBirthdate(final DateTime? value) {
    userBirthdate = value;
    if (value != null) {
      birthDateController.text = '${value.day}/${value.month}/${value.year}';
    } else {
      birthDateController.text = '';
    }
    notifyListeners();
  }

  void setMeetStory(final String value) {
    if (meetStoryController.text != value) {
      meetStoryController.text = value;
      notifyListeners();
    }
  }

  void setUserCountryCode(final String value) {
    userCountryCode = value.trim().toUpperCase();
    notifyListeners();
  }

  void setAiCountryCode(final String value) {
    aiCountryCode = value.trim().toUpperCase();
    notifyListeners();
  }

  /// Forwarder for suggestStory that existed on the provider. It delegates to
  /// the same helper used previously via OnboardingUtils through the use case.
  Future<void> suggestStory(final BuildContext context) async {
    try {
      if (userNameController.text.isNotEmpty &&
          aiNameController.text.isNotEmpty) {
        _setLoading(true);
        meetStoryController.text = 'Generando historia...';
        final storyText = await OnboardingUtils.generateMeetStoryFromContext(
          userName: userNameController.text,
          aiName: aiNameController.text,
          userCountry: userCountryCode,
          aiCountry: aiCountryCode,
          userBirthdate: userBirthdate,
        );

        if (storyText.toLowerCase().contains('error')) {
          _setError(storyText);
          meetStoryController.text = '';
        } else {
          meetStoryController.text = storyText.trim();
        }
      }
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  String get birthDateText => birthDateController.text;

  @override
  void dispose() {
    try {
      userNameController.dispose();
      aiNameController.dispose();
      meetStoryController.dispose();
      birthDateController.dispose();
    } catch (_) {}
    super.dispose();
  }

  /// Limpia el mensaje de error
  void clearError() {
    _clearError();
  }

  // --- Métodos privados ---

  void _setLoading(final bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(final String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
