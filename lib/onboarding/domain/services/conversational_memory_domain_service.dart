import 'package:ai_chan/onboarding/domain/value_objects/onboarding_validation_config.dart';
import 'package:ai_chan/shared.dart'; // Para acceder a LocaleUtils

/// Servicio de dominio que contiene las reglas de negocio para validación
/// y procesamiento de datos del onboarding conversacional
/// REFACTORED: Usando shared kernel para dependencias comunes
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
        return OnboardingValidationConfig.validateUserName(extractedValue);
      case 'userCountry':
        return _validateCountry(extractedValue);
      case 'userBirthdate':
        return OnboardingValidationConfig.validateBirthdate(extractedValue);
      case 'aiCountry':
        return _validateCountry(extractedValue);
      case 'aiName':
        return OnboardingValidationConfig.validateAiName(extractedValue);
      case 'meetStory':
        return OnboardingValidationConfig.validateMeetStory(extractedValue);
      default:
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'Tipo de dato no reconocido: $stepName',
        };
    }
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

    // Buscar el código por nombre
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

  /// Obtiene el nivel de recuperación de memoria basado en el porcentaje de completitud
  static Map<String, String> _getMemoryRecoveryLevel(
    final double completionPercentage,
  ) {
    return OnboardingValidationConfig.getMemoryRecoveryLevel(
      completionPercentage,
    );
  }

  /// Configuración de voz dinámica: genera instrucciones para TTS según estado
  static Map<String, String> getVoiceInstructions({
    final String? userCountry,
    final String? aiCountry,
    final double? completionPercentage,
  }) {
    final userLang = userCountry != null
        ? LocaleUtils.languageNameEsForCountry(userCountry)
        : 'Español';

    // Obtener el nivel de recuperación de memoria para emoción y descripción
    final memoryLevel = _getMemoryRecoveryLevel(completionPercentage ?? 0.0);

    String accentInstructions = '';

    // Prioridad: país de la IA > país del usuario > neutro
    if (aiCountry != null) {
      final aiCountryName =
          CountriesEs.codeToName[aiCountry.toUpperCase()] ?? aiCountry;
      accentInstructions =
          'Habla $userLang con acento de $aiCountryName, ya que ese es tu país de origen.';
    } else if (userCountry != null) {
      final userCountryName =
          CountriesEs.codeToName[userCountry.toUpperCase()] ?? userCountry;
      accentInstructions =
          'Habla $userLang con acento de $userCountryName, adaptándote al país del usuario.';
    } else {
      accentInstructions =
          'Usa un acento español neutro con un toque misterioso, como si vinieras de tierras lejanas.';
    }

    return {
      'emotion': memoryLevel['emotion']!,
      'descripcion': memoryLevel['description']!,
      'voice': accentInstructions,
    };
  }
}
