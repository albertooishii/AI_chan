import 'package:ai_chan/onboarding/domain/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';

/// Adaptador canónico de perfil: delega la generación de biografía y apariencia
/// a los generadores existentes usando el nuevo sistema AIProviderManager.
///
/// Permite generar perfiles completos para el onboarding.
class ProfileAdapter implements IProfileService {
  /// Constructor simplificado que usa el nuevo sistema AIProviderManager.
  const ProfileAdapter();

  @override
  Future<AiChanProfile> generateBiography({
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    try {
      // Use the new AIProviderManager system directly
      return await generateAIBiographyWithAI(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
    } on Exception catch (e) {
      // Fallback determinista para entornos sin claves
      return AiChanProfile(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        aiBirthdate: DateTime.now(),
        biography: {
          'summary':
              'Generated fallback biography for $aiName due to unavailable remote service.',
          'note': e.toString(),
        },
        appearance: {'style': 'fallback'},
      );
    }
  }

  @override
  Future<AiImage?> generateAppearance(final AiChanProfile profile) async {
    try {
      final generator = IAAppearanceGenerator();
      final appearanceMap = await generator.generateAppearanceFromBiography(
        profile,
      );
      // Generate avatar (replace existing) and return it
      final updatedProfile = profile.copyWith(appearance: appearanceMap);
      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
        updatedProfile,
      );
      return avatar;
    } on Exception {
      return AiImage(
        url: 'https://example.com/avatar_placeholder.png',
        seed: 'fallback-seed',
        prompt: 'fallback',
      );
    }
  }

  @override
  Future<void> saveProfile(final AiChanProfile profile) async {
    return;
  }
}
