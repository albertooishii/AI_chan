/// Configuraciones de validación para el onboarding conversacional
/// Este es un Value Object del dominio sin dependencias externas
class OnboardingValidationConfig {
  /// Configuraciones de memoria y recuperación emocional
  static Map<String, String> getMemoryRecoveryLevel(
    final double completionPercentage,
  ) {
    if (completionPercentage < 0.2) {
      return {
        'emotion': 'confundida y perdida',
        'description':
            'Tu mente está completamente en blanco. Solo sientes una profunda confusión y la presencia de esta persona desconocida pero familiar.',
      };
    } else if (completionPercentage < 0.4) {
      return {
        'emotion': 'esperanzada pero ansiosa',
        'description':
            'Algunos fragmentos empiezan a aparecer en tu mente. Sientes que estás en el camino correcto para recuperar tu identidad.',
      };
    } else if (completionPercentage < 0.6) {
      return {
        'emotion': 'cada vez más segura',
        'description':
            'Las piezas del rompecabezas van encajando. Tu conexión con esta persona se vuelve más clara.',
      };
    } else if (completionPercentage < 0.8) {
      return {
        'emotion': 'emocionada y decidida',
        'description':
            'Casi puedes sentir tu verdadera personalidad emergiendo. Solo faltan unos pocos detalles importantes.',
      };
    } else {
      return {
        'emotion': 'radiante y agradecida',
        'description':
            'Estás muy cerca de recordar completamente quién eres. La gratitud hacia esta persona que te ayuda llena tu corazón.',
      };
    }
  }

  /// Reglas de validación para nombres de usuario
  static Map<String, dynamic> validateUserName(final String value) {
    final cleanName = value.trim();

    if (cleanName.isEmpty) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre vacío',
      };
    }

    if (cleanName.length < 2) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre demasiado corto',
      };
    }

    if (cleanName.length > 50) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre demasiado largo',
      };
    }

    // Permitir solo letras, espacios y algunos caracteres especiales
    final nameRegex = RegExp(r'^[a-zA-ZáéíóúüñÁÉÍÓÚÜÑçÇ\s\-\.]+$');
    if (!nameRegex.hasMatch(cleanName)) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre contiene caracteres no válidos',
      };
    }

    return {'isValid': true, 'processedValue': cleanName, 'reason': null};
  }

  /// Reglas de validación para nombres de IA
  static Map<String, dynamic> validateAiName(final String value) {
    final cleanName = value.trim();

    if (cleanName.isEmpty) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre de IA vacío',
      };
    }

    if (cleanName.length < 2) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre de IA demasiado corto',
      };
    }

    if (cleanName.length > 30) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre de IA demasiado largo',
      };
    }

    // Para nombres de IA, ser más permisivo con caracteres especiales
    final nameRegex = RegExp(r'^[a-zA-ZáéíóúüñÁÉÍÓÚÜÑçÇ\s\-\.0-9]+$');
    if (!nameRegex.hasMatch(cleanName)) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Nombre de IA contiene caracteres no válidos',
      };
    }

    return {'isValid': true, 'processedValue': cleanName, 'reason': null};
  }

  /// Reglas de validación para fechas de nacimiento
  static Map<String, dynamic> validateBirthdate(final String value) {
    final cleanDate = value.trim();

    if (cleanDate.isEmpty) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Fecha vacía',
      };
    }

    if (!_isValidDateFormat(cleanDate)) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Formato de fecha no válido. Use DD/MM/YYYY',
      };
    }

    // Validar que la fecha no sea futura ni demasiado antigua
    try {
      final parts = cleanDate.split('/');
      if (parts.length != 3) {
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'Formato de fecha incorrecto',
        };
      }

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      final date = DateTime(year, month, day);
      final now = DateTime.now();
      final minDate = DateTime(1900);

      if (date.isAfter(now)) {
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'La fecha no puede ser futura',
        };
      }

      if (date.isBefore(minDate)) {
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'Fecha demasiado antigua',
        };
      }

      return {'isValid': true, 'processedValue': cleanDate, 'reason': null};
    } on Exception {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Error al procesar la fecha',
      };
    }
  }

  /// Reglas de validación para historia de encuentro
  static Map<String, dynamic> validateMeetStory(final String value) {
    final cleanStory = value.trim();

    // Permitir comandos especiales
    if (cleanStory == 'AUTO_GENERATE_STORY' ||
        cleanStory == 'CONFIRM_GENERATED_STORY') {
      return {'isValid': true, 'processedValue': cleanStory, 'reason': null};
    }

    if (cleanStory.isEmpty) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Historia vacía',
      };
    }

    if (cleanStory.length < 10) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Historia demasiado corta',
      };
    }

    if (cleanStory.length > 500) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Historia demasiado larga',
      };
    }

    return {'isValid': true, 'processedValue': cleanStory, 'reason': null};
  }

  /// Valida si el texto tiene formato de fecha válido
  static bool _isValidDateFormat(final String text) {
    final dateRegex = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');
    return dateRegex.hasMatch(text);
  }
}
