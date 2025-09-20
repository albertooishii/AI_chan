import 'package:ai_chan/shared.dart';
// Removed: i_chat_export_service.dart - using ISharedChatRepository directly
import 'package:ai_chan/onboarding/domain/interfaces/i_onboarding_persistence_service.dart';
import 'dart:convert';

/// Use Case for Biography Generation
/// Encapsulates the business logic for creating AI character biographies
/// Following Clean Architecture principles - no UI dependencies
class BiographyGenerationUseCase {
  BiographyGenerationUseCase({
    required this.profileService,
    required this.chatExportService,
    required this.onboardingPersistenceService,
    final IAAppearanceGenerator? appearanceGenerator,
    final IAAvatarGenerator? avatarGenerator,
  }) : _appearanceGenerator = appearanceGenerator ?? IAAppearanceGenerator(),
       _avatarGenerator = avatarGenerator ?? IAAvatarGenerator();

  final IProfileService profileService;
  final ISharedChatRepository chatExportService;
  final IOnboardingPersistenceService onboardingPersistenceService;
  final IAAppearanceGenerator _appearanceGenerator;
  final IAAvatarGenerator _avatarGenerator;

  /// Generates a complete AI biography with appearance and avatar
  /// Returns the generated profile or throws an exception
  Future<AiChanProfile> generateCompleteBiography({
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
    final void Function(BiographyGenerationStep)? onProgress,
  }) async {
    // Validate input parameters first
    if (!_isValidInput(
      userName: userName,
      aiName: aiName,
      userBirthdate: userBirthdate,
      meetStory: meetStory,
    )) {
      throw ArgumentError('Invalid input parameters for biography generation');
    }

    try {
      // Step 1: Generate basic biography
      onProgress?.call(BiographyGenerationStep.generatingBiography);

      final biography = await profileService.generateBiography(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
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

      // Step 5: Save to storage with timeline entry for meetStory
      onProgress?.call(BiographyGenerationStep.saving);
      try {
        // Create timeline entry for meetStory (level -1 indicates origin story)
        final meetStoryTimelineEntry = TimelineEntry(
          resume: meetStory,
          level: -1,
        );

        // Create ChatExport with the biography and timeline
        final chatExport = ChatExport(
          profile: finalBiography,
          messages: [],
          events: [],
          timeline: [meetStoryTimelineEntry],
        );

        // Save the complete chat export (includes biography and timeline)
        await chatExportService.saveAll(chatExport.toJson());
      } on Exception catch (e) {
        // Log persistence failures to help debugging on devices
        try {
          Log.e(
            'BiographyGenerationUseCase: failed to save biography: $e',
            tag: 'BIO_GEN',
          );
        } on Exception catch (_) {}
        rethrow;
      }

      onProgress?.call(BiographyGenerationStep.completed);

      return finalBiography;
    } on Exception catch (e) {
      onProgress?.call(BiographyGenerationStep.error);
      throw Exception('Biography generation failed: $e');
    }
  }

  /// Loads existing biography from storage
  Future<AiChanProfile?> loadExistingBiography() async {
    try {
      final jsonStr = await onboardingPersistenceService.getOnboardingData();
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return AiChanProfile.tryFromJson(json);
      }
      return null;
    } on Exception catch (e) {
      throw Exception('Failed to load existing biography: $e');
    }
  }

  /// Validates biography generation parameters
  static bool _isValidInput({
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
  }) {
    return userName.trim().isNotEmpty &&
        aiName.trim().isNotEmpty &&
        meetStory.trim().isNotEmpty &&
        userBirthdate != null &&
        userBirthdate.isBefore(DateTime.now());
  }

  /// Clears saved biography from storage
  Future<void> clearSavedBiography() async {
    await onboardingPersistenceService.removeOnboardingData();
    await onboardingPersistenceService.removeChatHistory();
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
