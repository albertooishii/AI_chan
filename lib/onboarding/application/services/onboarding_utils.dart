import 'package:ai_chan/shared.dart';

/// Utilidades específicas para el proceso de onboarding
class OnboardingUtils {
  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  /// Delega al generador especializado de meetstory
  static Future<String> generateMeetStoryFromContext({
    required final String userName,
    required final String aiName,
    final String? userCountry,
    final String? aiCountry,
    final DateTime? userBirthdate,
  }) async {
    final generator = IAMeetStoryGenerator();
    return await generator.generateMeetStoryFromContext(
      userName: userName,
      aiName: aiName,
      userCountry: userCountry,
      aiCountry: aiCountry,
      userBirthdate: userBirthdate,
    );
  }
}
