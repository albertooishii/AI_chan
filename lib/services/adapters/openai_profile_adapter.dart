import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';

class OpenAIProfileAdapter implements IProfileService {
  final IAIService aiService;
  OpenAIProfileAdapter(this.aiService);

  @override
  Future<AiChanProfile> generateBiography({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  }) async {
    // Delegar la generación de biografía al generador original
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
    // Genera la apariencia usando el generador por defecto
    final generator = IAAppearanceGenerator();
    final result = await generator.generateAppearancePromptWithImage(profile, aiService: null);
    return result['avatar'] as AiImage?;
  }

  @override
  Future<void> saveProfile(AiChanProfile profile) async {
    // Guardar en prefs (puede ser reemplazado por IStorageService en el futuro)
    // Aquí solo ejemplo local
    // ...
  }
}
