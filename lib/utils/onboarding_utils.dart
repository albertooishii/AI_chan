import 'package:ai_chan/core/models.dart';
import '../services/ia_bio_generator.dart';
import '../services/ia_appearance_generator.dart';
import 'package:ai_chan/core/models/image.dart' as models;

/// Utilidad flexible para crear la biografía completa (con apariencia), permitiendo elegir el generador
Future<AiChanProfile> generateFullBiographyFlexible({
  required String userName,
  required String aiName,
  required DateTime userBirthday,
  required String meetStory,
  required IAAppearanceGenerator appearanceGenerator,
  String? userCountryCode,
  String? aiCountryCode,
}) async {
  final bio = await generateAIBiographyWithAI(
    userName: userName,
    aiName: aiName,
    userBirthday: userBirthday,
    meetStory: meetStory,
    userCountryCode: userCountryCode,
    aiCountryCode: aiCountryCode,
  );
  final appearanceResult = await appearanceGenerator.generateAppearancePromptWithImage(bio, aiService: null);
  // Extraer avatar: el generador devuelve 'avatar' como Image
  final models.AiImage? avatar = appearanceResult['avatar'] as models.AiImage?;
  final biography = AiChanProfile(
    biography: bio.biography,
    userName: bio.userName,
    aiName: bio.aiName,
    userBirthday: bio.userBirthday,
    aiBirthday: bio.aiBirthday,
    appearance: appearanceResult['appearance'] as Map<String, dynamic>? ?? <String, dynamic>{},
    userCountryCode: userCountryCode ?? bio.userCountryCode,
    aiCountryCode: aiCountryCode ?? bio.aiCountryCode,
    avatar: avatar,
    timeline: bio.timeline, // timeline SIEMPRE al final
  );
  return biography;
}
