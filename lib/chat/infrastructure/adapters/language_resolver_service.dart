import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
// TODO: Replace GoogleSpeechService with new Voice bounded context services

/// Implementation of language resolver that detects language codes for TTS voices
/// Specializes in Google TTS voice format detection
/// TODO: Migrate to use new Voice bounded context
class LanguageResolverService implements ILanguageResolver {
  @override
  Future<String> resolveLanguageCode(final String voiceName) async {
    try {
      // Detectar si es una voz de Google (formato: "es-ES-Standard-A", "en-US-Wavenet-D")
      final googleVoicePattern = RegExp(
        r'^[a-z]{2}-[A-Z]{2}-(Standard|Wavenet|Neural2)-[A-Z]$',
      );

      if (googleVoicePattern.hasMatch(voiceName)) {
        // Extraer el código de idioma del nombre de la voz (ej: "es-ES" de "es-ES-Standard-A")
        final parts = voiceName.split('-');
        if (parts.length >= 2) {
          final languageCode = '${parts[0]}-${parts[1]}';

          // TODO: Replace with new Voice bounded context service
          // For now, return the detected language code directly
          return languageCode;
        }
      }

      // Si no es Google o no se pudo resolver, usar idioma por defecto
      final fallbackLang =
          await PrefsUtils.getRawString('user_language') ?? 'es-ES';
      return fallbackLang;
    } on Exception {
      return await PrefsUtils.getRawString('user_language') ?? 'es-ES';
    }
  }
}
