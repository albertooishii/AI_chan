import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';

/// Utilidad flexible para crear la biografía completa (con apariencia), permitiendo elegir el generador
Future<AiChanProfile> generateFullBiographyFlexible({
  required String userName,
  required String aiName,
  required DateTime userBirthday,
  required String meetStory,
  required IAAppearanceGenerator appearanceGenerator,
  Future<String?> Function(String base64, {String prefix})? saveImageFunc,
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
  final appearanceMap = await appearanceGenerator.generateAppearancePrompt(
    bio,
    aiService: null,
    saveImageFunc: saveImageFunc,
  );
  final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
    bio,
    appearanceMap,
    aiService: null,
    saveImageFunc: saveImageFunc,
  );
  final biography = AiChanProfile(
    biography: bio.biography,
    userName: bio.userName,
    aiName: bio.aiName,
    userBirthday: bio.userBirthday,
    aiBirthday: bio.aiBirthday,
    appearance: appearanceMap as Map<String, dynamic>? ?? <String, dynamic>{},
    userCountryCode: userCountryCode ?? bio.userCountryCode,
    aiCountryCode: aiCountryCode ?? bio.aiCountryCode,
    avatars: [avatar],
    timeline: bio.timeline, // timeline SIEMPRE al final
  );
  return biography;
}
