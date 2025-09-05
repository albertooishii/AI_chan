import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/application/use_cases/form_onboarding_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/import_export_onboarding_use_case.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/di.dart' as di;

/// Controller para el onboarding por formulario
/// Coordina la UI con los casos de uso, manteniendo la separación de responsabilidades
class FormOnboardingController extends ChangeNotifier {
  final FormOnboardingUseCase _formUseCase;
  final ImportExportOnboardingUseCase _importExportUseCase;

  // Estado del controller
  bool _isLoading = false;
  String? _errorMessage;
  ImportedChat? _importedData;

  FormOnboardingController({FormOnboardingUseCase? formUseCase, ImportExportOnboardingUseCase? importExportUseCase})
    : _formUseCase = formUseCase ?? FormOnboardingUseCase(),
      _importExportUseCase = importExportUseCase ?? ImportExportOnboardingUseCase(fileService: di.getFileService());

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ImportedChat? get importedData => _importedData;
  bool get hasError => _errorMessage != null;

  /// Valida si el formulario está completo
  bool isFormComplete({
    required String userName,
    required String aiName,
    required String birthDateText,
    required String meetStory,
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
    required String userName,
    required String aiName,
    required String birthDateText,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      Log.d('🎯 Procesando formulario de onboarding', tag: 'FORM_ONBOARDING_CTRL');

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
      return OnboardingFormResult(success: false, errors: ['Error inesperado: $e']);
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
    Future<ImportExportResult> Function() operation,
    String startMessage,
    String successMessage,
    String cancelMessage,
    String errorPrefix,
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

  /// Limpia el mensaje de error
  void clearError() {
    _clearError();
  }

  // --- Métodos privados ---

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
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
