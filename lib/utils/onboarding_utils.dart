import '../models/ai_chan_profile.dart';
import '../services/ia_bio_generator.dart';
import '../services/ia_appearance_generator.dart';
import '../models/image.dart';

/// Utilidad flexible para crear la biografía completa (con apariencia), permitiendo elegir el generador
Future<AiChanProfile> generateFullBiographyFlexible({
  required String userName,
  required String aiName,
  required DateTime userBirthday,
  required String meetStory,
  required IAAppearanceGenerator appearanceGenerator,
}) async {
  final bio = await generateAIBiographyWithAI(
    userName: userName,
    aiName: aiName,
    userBirthday: userBirthday,
    meetStory: meetStory,
  );
  final appearanceResult = await appearanceGenerator.generateAppearancePromptWithImage(
    bio,
    aiService: null,
    model: 'gemini-2.5-flash',
    imageModel: 'gpt-5-mini',
  );
  final biography = AiChanProfile(
    personality: bio.personality,
    biography: bio.biography,
    userName: bio.userName,
    aiName: bio.aiName,
    userBirthday: bio.userBirthday,
    aiBirthday: bio.aiBirthday,
    appearance: appearanceResult['appearance'] as Map<String, dynamic>? ?? <String, dynamic>{},
    avatar: Image(
      seed: appearanceResult['imageId'] as String?,
      url: appearanceResult['imageUrl'] as String?,
      prompt: appearanceResult['revisedPrompt'] as String?,
    ),
    timeline: bio.timeline, // timeline SIEMPRE al final
  );
  return biography;
}
