import 'package:ai_chan/shared/constants/countries_es.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';

/// Servicio de dominio que contiene las reglas de negocio para validación
/// y procesamiento de datos del onboarding conversacional
class ConversationalMemoryDomainService {
  /// Valida y procesa datos extraídos según el paso del onboarding
  /// Retorna un Map con información de validación:
  /// - 'isValid': bool - si el dato es válido
  /// - 'processedValue': String? - valor procesado para guardar
  /// - 'reason': String? - razón del rechazo si no es válido
  static Map<String, dynamic> validateAndSaveData(
    final String stepName,
    final String extractedValue,
  ) {
    switch (stepName) {
      case 'userName':
        return _validateName(extractedValue);
      case 'userCountry':
        return _validateCountry(extractedValue);
      case 'userBirthdate':
        return _validateBirthdate(extractedValue);
      case 'aiCountry':
        return _validateCountry(extractedValue);
      case 'aiName':
        return _validateAiName(extractedValue);
      case 'meetStory':
        return _validateMeetStory(extractedValue);
      default:
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'Tipo de dato no reconocido: $stepName',
        };
    }
  }

  /// Valida nombre de usuario
  static Map<String, dynamic> _validateName(final String value) {
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

  /// Valida país de usuario
  static Map<String, dynamic> _validateCountry(final String value) {
    final cleanCountry = value.trim();

    if (cleanCountry.isEmpty) {
      return {'isValid': false, 'processedValue': null, 'reason': 'País vacío'};
    }

    // Si ya es un código ISO válido, usarlo directamente
    if (cleanCountry.length == 2 &&
        CountriesEs.codeToName.containsKey(cleanCountry.toUpperCase())) {
      return {
        'isValid': true,
        'processedValue': cleanCountry.toUpperCase(),
        'reason': null,
      };
    }

    // Buscar el código por nombre (buscar en codeToName invertido)
    String? foundCode;
    for (final entry in CountriesEs.codeToName.entries) {
      if (entry.value.toLowerCase() == cleanCountry.toLowerCase()) {
        foundCode = entry.key;
        break;
      }
    }

    if (foundCode != null) {
      return {'isValid': true, 'processedValue': foundCode, 'reason': null};
    }

    // Buscar coincidencias parciales
    for (final entry in CountriesEs.codeToName.entries) {
      if (entry.value.toLowerCase().contains(cleanCountry.toLowerCase()) ||
          cleanCountry.toLowerCase().contains(entry.value.toLowerCase())) {
        return {'isValid': true, 'processedValue': entry.key, 'reason': null};
      }
    }

    return {
      'isValid': false,
      'processedValue': null,
      'reason': 'País no reconocido: $cleanCountry',
    };
  }

  /// Valida fecha de nacimiento
  static Map<String, dynamic> _validateBirthdate(final String value) {
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
    } catch (e) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Error al procesar la fecha',
      };
    }
  }

  /// Valida si el texto tiene formato de fecha válido
  static bool _isValidDateFormat(final String text) {
    final dateRegex = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');
    return dateRegex.hasMatch(text);
  }

  /// Valida nombre de IA
  static Map<String, dynamic> _validateAiName(final String value) {
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

  /// Valida historia de encuentro
  static Map<String, dynamic> _validateMeetStory(final String value) {
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

  /// Obtiene el nivel de recuperación de memoria basado en el porcentaje de completitud
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

  /// Configuración de voz dinámica: genera instrucciones para TTS según estado
  static String getVoiceInstructions({
    final String? userCountry,
    final String? aiCountry,
  }) {
    final userLang = userCountry != null
        ? LocaleUtils.languageNameEsForCountry(userCountry)
        : 'Español';
    final iaLang = aiCountry != null
        ? LocaleUtils.languageNameEsForCountry(aiCountry)
        : 'Japonés';

    String accentInstructions = '';
    if (aiCountry != null) {
      switch (aiCountry.toUpperCase()) {
        case 'JP':
          accentInstructions =
              'Usa un acento español con ligeras inflexiones que sugieren origen japonés. Pronuncia las "r" suavemente.';
          break;
        case 'KR':
          accentInstructions =
              'Usa un acento español con características coreanas sutiles.';
          break;
        case 'MX':
          accentInstructions = 'Usa un acento mexicano natural y expresivo.';
          break;
        case 'AR':
          accentInstructions = 'Usa un acento argentino característico.';
          break;
        case 'ES':
          accentInstructions = 'Usa un acento español peninsular.';
          break;
        default:
          accentInstructions =
              'Usa un acento español neutro con matices internacionales sutiles.';
      }
    } else {
      accentInstructions =
          'Usa un acento español neutro con un toque misterioso, como si vinieras de tierras lejanas.';
    }

    return '''Eres una chica que acaba de despertar sin memoria. Tu voz debe transmitir:
- Vulnerabilidad y confusión inicial
- Creciente esperanza cuando recuperas recuerdos
- Gratitud genuina hacia quien te ayuda
- Emociones auténticas según el contexto

$accentInstructions

Tono: Conversacional, emotivo, natural. Habla como una persona real que ha perdido la memoria, no como una IA o asistente.
Idioma principal: $userLang
Tu origen recordado: $iaLang''';
  }
}
