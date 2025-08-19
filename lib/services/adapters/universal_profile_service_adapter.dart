import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';

/// Servicio universal para generación de perfil, configurable por modelo desde .env
class UniversalProfileServiceAdapter implements IProfileService {
  @override
  Future<AiChanProfile> generateBiography({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  }) async {
    // Delegar al generador único, que ya usa DEFAULT_TEXT_MODEL
    return await generateAIBiographyWithAI(
      userName: userName,
      aiName: aiName,
      userBirthday: userBirthday,
      meetStory: meetStory,
      userCountryCode: userCountryCode,
      aiCountryCode: aiCountryCode,
    );
  }

  @override
  Future<AiImage?> generateAppearance(AiChanProfile profile) async {
    final result = await IAAppearanceGenerator().generateAppearancePromptWithImage(profile);
    return result['avatar'] as AiImage?;
  }

  @override
  Future<void> saveProfile(AiChanProfile profile) async {
    // Implementación de guardado (puede ser local o por IStorageService)
    // ...
  }
}
