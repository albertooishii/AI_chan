import 'package:ai_chan/shared/utils/log_utils.dart';

/// Use Case que maneja la lógica del onboarding por formulario
/// Extrae la lógica de validación y procesamiento de datos del formulario
class FormOnboardingUseCase {
  FormOnboardingUseCase();

  /// Valida y procesa los datos del formulario de onboarding
  Future<OnboardingFormResult> processFormData({
    required String userName,
    required String aiName,
    required String birthDateText,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  }) async {
    Log.d(
      '📝 Procesando datos del formulario de onboarding',
      tag: 'FORM_ONBOARDING_UC',
    );

    final errors = <String>[];

    // Validar datos requeridos
    if (userName.trim().isEmpty) {
      errors.add('El nombre de usuario es obligatorio');
    }

    if (aiName.trim().isEmpty) {
      errors.add('El nombre de AI-chan es obligatorio');
    }

    if (meetStory.trim().isEmpty) {
      errors.add('La historia de cómo os conocísteis es obligatoria');
    }

    // Validar y parsear fecha de nacimiento
    DateTime? userBirthday;
    if (birthDateText.trim().isEmpty) {
      errors.add('La fecha de nacimiento es obligatoria');
    } else {
      userBirthday = _parseBirthDate(birthDateText);
      if (userBirthday == null) {
        errors.add('La fecha de nacimiento no es válida');
      } else {
        // Validar que la fecha sea razonable
        final now = DateTime.now();
        final age = now.year - userBirthday.year;

        if (age < 13 || age > 120) {
          errors.add('La edad debe estar entre 13 y 120 años');
        }
      }
    }

    // Si hay errores, retornar resultado con errores
    if (errors.isNotEmpty) {
      return OnboardingFormResult(success: false, errors: errors);
    }

    // Datos válidos, retornar resultado exitoso
    return OnboardingFormResult(
      success: true,
      userName: userName.trim(),
      aiName: aiName.trim(),
      userBirthday: userBirthday!,
      meetStory: meetStory.trim(),
      userCountryCode: userCountryCode,
      aiCountryCode: aiCountryCode,
    );
  }

  /// Valida si un formulario está completo
  bool isFormComplete({
    required String userName,
    required String aiName,
    required String birthDateText,
    required String meetStory,
  }) {
    return userName.trim().isNotEmpty &&
        aiName.trim().isNotEmpty &&
        birthDateText.trim().isNotEmpty &&
        meetStory.trim().isNotEmpty &&
        _parseBirthDate(birthDateText) != null;
  }

  // --- Métodos privados ---

  /// Parsea una fecha en formato DD/MM/YYYY
  DateTime? _parseBirthDate(String dateText) {
    try {
      final parts = dateText.trim().split('/');
      if (parts.length != 3) return null;

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      final date = DateTime(year, month, day);

      // Validar que la fecha sea válida (no sea futura, etc.)
      if (date.isAfter(DateTime.now())) {
        return null;
      }

      return date;
    } catch (e) {
      Log.w('Error parsing birth date "$dateText": $e');
      return null;
    }
  }
}

/// Resultado del procesamiento del formulario de onboarding
class OnboardingFormResult {
  final bool success;
  final List<String> errors;
  final String? userName;
  final String? aiName;
  final DateTime? userBirthday;
  final String? meetStory;
  final String? userCountryCode;
  final String? aiCountryCode;

  const OnboardingFormResult({
    required this.success,
    this.errors = const [],
    this.userName,
    this.aiName,
    this.userBirthday,
    this.meetStory,
    this.userCountryCode,
    this.aiCountryCode,
  });

  /// Indica si hay errores de validación
  bool get hasErrors => errors.isNotEmpty;

  /// Mensaje de error concatenado
  String get errorMessage => errors.join('\n');
}
