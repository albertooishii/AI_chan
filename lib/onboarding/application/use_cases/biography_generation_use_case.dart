import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'dart:convert';

/// Use Case for Biography Generation
/// Encapsulates the business logic for creating AI character biographies
/// Following Clean Architecture principles - no UI dependencies
class BiographyGenerationUseCase {
  final IProfileService _profileService;
  final IAAppearanceGenerator _appearanceGenerator;
  final IAAvatarGenerator _avatarGenerator;

  BiographyGenerationUseCase({
    IProfileService? profileService,
    IAAppearanceGenerator? appearanceGenerator,
    IAAvatarGenerator? avatarGenerator,
  }) : _profileService = profileService ?? di.getProfileServiceForProvider(),
       _appearanceGenerator = appearanceGenerator ?? IAAppearanceGenerator(),
       _avatarGenerator = avatarGenerator ?? IAAvatarGenerator();

  /// Generates a complete AI biography with appearance and avatar
  /// Returns the generated profile or throws an exception
  Future<AiChanProfile> generateCompleteBiography({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    void Function(BiographyGenerationStep)? onProgress,
  }) async {
    try {
      // Step 1: Generate basic biography
      onProgress?.call(BiographyGenerationStep.generatingBiography);

      final biography = await _profileService.generateBiography(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );

      // Step 2: Generate appearance
      onProgress?.call(BiographyGenerationStep.generatingAppearance);

      final appearanceMap = await _appearanceGenerator
          .generateAppearanceFromBiography(biography);

      // Step 3: Generate avatar
      onProgress?.call(BiographyGenerationStep.generatingAvatar);

      final updatedBiography = biography.copyWith(appearance: appearanceMap);
      final avatar = await _avatarGenerator.generateAvatarFromAppearance(
        updatedBiography,
      );

      // Step 4: Finalize
      onProgress?.call(BiographyGenerationStep.finalizing);

      final finalBiography = updatedBiography.copyWith(avatars: [avatar]);

      // Step 5: Save to storage
      onProgress?.call(BiographyGenerationStep.saving);
      await _saveBiographyToStorage(finalBiography);

      onProgress?.call(BiographyGenerationStep.completed);

      return finalBiography;
    } catch (e) {
      onProgress?.call(BiographyGenerationStep.error);
      throw Exception('Biography generation failed: $e');
    }
  }

  /// Loads existing biography from storage
  Future<AiChanProfile?> loadExistingBiography() async {
    try {
      final jsonStr = await PrefsUtils.getOnboardingData();
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return await AiChanProfile.tryFromJson(json);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to load existing biography: $e');
    }
  }

  /// Validates biography generation parameters
  bool validateParameters({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
  }) {
    return userName.trim().isNotEmpty &&
        aiName.trim().isNotEmpty &&
        meetStory.trim().isNotEmpty &&
        userBirthday.isBefore(DateTime.now());
  }

  /// Checks if a complete biography exists in storage
  Future<bool> hasCompleteBiography() async {
    try {
      final biography = await loadExistingBiography();
      return biography != null && biography.avatars?.isNotEmpty == true;
    } catch (e) {
      return false;
    }
  }

  /// Saves biography to persistent storage
  Future<void> _saveBiographyToStorage(AiChanProfile biography) async {
    final jsonBio = jsonEncode(biography.toJson());
    await PrefsUtils.setOnboardingData(jsonBio);
  }

  /// Clears saved biography from storage
  Future<void> clearSavedBiography() async {
    await PrefsUtils.removeOnboardingData();
    await PrefsUtils.removeChatHistory();
  }
}

/// Steps in the biography generation process
enum BiographyGenerationStep {
  generatingBiography,
  generatingAppearance,
  generatingAvatar,
  finalizing,
  saving,
  completed,
  error,
}
