import '../models/ai_chan_profile.dart';
import '../services/ia_bio_generator.dart';
import '../services/ia_appearance_generator.dart';

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
  final appearance = await appearanceGenerator.generateAppearancePrompt(bio);
  final biography = AiChanProfile(
    personality: bio.personality,
    biography: bio.biography,
    timeline: bio.timeline,
    userName: bio.userName,
    aiName: bio.aiName,
    userBirthday: bio.userBirthday,
    aiBirthday: bio.aiBirthday,
    appearance: appearance,
  );
  return biography;
}
