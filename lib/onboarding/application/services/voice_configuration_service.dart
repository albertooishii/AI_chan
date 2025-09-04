import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/onboarding/domain/entities/onboarding_state.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Servicio que maneja la configuración dinámica de voz para el onboarding
class VoiceConfigurationService {
  /// Genera la configuración de voz basada en el estado actual del onboarding
  Map<String, dynamic> getVoiceConfiguration(OnboardingState state) {
    final aiCountry = state.aiCountry;

    if (aiCountry == null || aiCountry.isEmpty) {
      // Configuración por defecto para etapas tempranas
      return _getDefaultConfiguration();
    }

    return _getConfigurationForCountry(aiCountry);
  }

  /// Genera instrucciones de pronunciación específicas para un país
  String getAccentInstructions(String? aiCountry) {
    if (aiCountry == null || aiCountry.isEmpty) {
      return 'Habla con voz femenina joven y dulce, con acento neutro en español.';
    }

    final aiCountryName = LocaleUtils.countryNameEs(aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(aiCountry);
    final isSpanishNative = _isSpanishNativeCountry(aiCountry);

    final String accentInstructions;
    if (isSpanishNative) {
      accentInstructions =
          'Habla español nativo con acento de $aiCountryName. '
          'Usa la pronunciación y entonación natural de una persona nacida en $aiCountryName.';
    } else {
      accentInstructions =
          'Habla español con acento $aiLanguageName de $aiCountryName. '
          'Pronuncia el español como una persona nativa de $aiCountryName que aprendió español como segundo idioma, '
          'manteniendo el acento y patrones de habla de su idioma original.';
    }

    final finalInstructions = 'Habla con voz femenina joven y dulce. $accentInstructions';

    Log.d('🎵 Instrucciones de voz generadas: "$finalInstructions"', tag: 'VOICE_CONFIG');
    return finalInstructions;
  }

  /// Determina si un país es hispanohablante nativo
  bool _isSpanishNativeCountry(String aiCountry) {
    final spanishCountries = LocaleUtils.speakSpanish();
    return spanishCountries.contains(aiCountry.toUpperCase());
  }

  // --- Métodos privados ---

  Map<String, dynamic> _getDefaultConfiguration() {
    return {
      'voice': 'marin',
      'model': 'tts-1-hd',
      'speed': 1.0,
      'instructions': 'Habla con voz femenina joven y dulce, con acento neutro en español.',
    };
  }

  Map<String, dynamic> _getConfigurationForCountry(String aiCountry) {
    final instructions = getAccentInstructions(aiCountry);

    // Ajustar parámetros según el país
    double speed = 1.0;
    const String voice = 'marin';

    // Personalizar velocidad según región (ejemplo)
    if (aiCountry.toLowerCase() == 'argentina') {
      speed = 1.1; // Los argentinos hablan un poco más rápido
    } else if (aiCountry.toLowerCase() == 'méxico') {
      speed = 0.95; // Habla un poco más pausada
    }

    return {'voice': voice, 'model': 'tts-1-hd', 'speed': speed, 'instructions': instructions};
  }
}
