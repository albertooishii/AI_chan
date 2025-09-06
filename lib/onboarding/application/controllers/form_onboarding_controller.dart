import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/domain/domain.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;

/// Controller para el onboarding por formulario
/// Coordina la UI con validación directa, manteniendo la separación de responsabilidades
class FormOnboardingController extends ChangeNotifier {
  FormOnboardingController();

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

  /// Valida si el formulario está completo - Direct validation
  bool isFormComplete({
    required final String userName,
    required final String aiName,
    required final String birthDateText,
    required final String meetStory,
  }) {
    return userName.trim().isNotEmpty &&
        aiName.trim().isNotEmpty &&
        birthDateText.trim().isNotEmpty &&
        meetStory.trim().isNotEmpty;
  }

  /// Procesa los datos del formulario - Direct processing with simple validation
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

      // Simple validation
      if (!isFormComplete(
        userName: userName,
        aiName: aiName,
        birthDateText: birthDateText,
        meetStory: meetStory,
      )) {
        _setError('Todos los campos son obligatorios');
        return OnboardingFormResult.failure(
          'Todos los campos son obligatorios',
        );
      }

      // Parse birth date
      final birthDate = DateTime.tryParse(birthDateText);
      if (birthDate == null) {
        _setError('Fecha de nacimiento inválida');
        return OnboardingFormResult.failure('Fecha de nacimiento inválida');
      }

      // Form is valid - return success result
      Log.d('✅ Formulario procesado exitosamente', tag: 'FORM_ONBOARDING_CTRL');
      return OnboardingFormResult.success(
        userName: userName,
        aiName: aiName,
        userBirthdate: birthDate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
    } on Exception catch (e) {
      Log.e('Error procesando formulario: $e', tag: 'FORM_ONBOARDING_CTRL');
      _setError('Error inesperado procesando el formulario: $e');
      return OnboardingFormResult.failure(
        'Error inesperado procesando el formulario: $e',
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Importa datos desde JSON - Direct implementation without use case
  Future<bool> importFromJson() async {
    _setLoading(true);
    _clearError();

    try {
      Log.d('📤 Iniciando importación JSON', tag: 'FORM_ONBOARDING_CTRL');

      final result = await chat_json_utils.ChatJsonUtils.importJsonFile();
      final String? jsonStr = result.$1;
      final String? error = result.$2;

      if (error != null) {
        _setError('Error importando JSON: $error');
        return false;
      }

      if (jsonStr == null || jsonStr.trim().isEmpty) {
        Log.d('🚫 Importación JSON cancelada', tag: 'FORM_ONBOARDING_CTRL');
        return false;
      }

      // TODO: Parse JSON data and set _importedData if needed
      Log.d('✅ Importación JSON exitosa', tag: 'FORM_ONBOARDING_CTRL');
      return true;
    } on Exception catch (e) {
      _setError('Error durante importación JSON: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Restaura desde un backup local - Simplified placeholder
  Future<bool> restoreFromLocalBackup() async {
    _setLoading(true);
    _clearError();

    try {
      Log.d(
        '📥 Restauración de backup no implementada',
        tag: 'FORM_ONBOARDING_CTRL',
      );
      return false;
    } on Exception catch (e) {
      _setError('Error durante restauración: $e');
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
    } on Exception catch (e) {
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
    } on Exception catch (_) {}
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
