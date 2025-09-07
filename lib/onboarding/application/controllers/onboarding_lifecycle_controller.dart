import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

/// Lifecycle controller that owns onboarding lifecycle state (biography loading,
/// saved/generated biography, import errors). This intentionally does NOT own
/// form controllers — those live in `FormOnboardingController`.
class OnboardingLifecycleController extends ChangeNotifier {
  OnboardingLifecycleController({
    final BiographyGenerationUseCase? biographyUseCase,
    required final IChatRepository chatRepository,
  }) : _biographyUseCase = biographyUseCase ?? BiographyGenerationUseCase(),
       _chatRepository = chatRepository {
    _loadExistingBiography();
  }
  final BiographyGenerationUseCase _biographyUseCase;
  final IChatRepository _chatRepository;

  bool loading = true;
  AiChanProfile? _generatedBiography;
  bool _biographySaved = false;
  String? importError;

  AiChanProfile? get generatedBiography => _generatedBiography;
  bool get biographySaved => _biographySaved;

  Future<void> _loadExistingBiography() async {
    try {
      final profile = await _biographyUseCase.loadExistingBiography();
      if (profile != null) {
        _generatedBiography = profile;
        _biographySaved = true;
        try {
          Log.i(
            'OnboardingLifecycle: loaded existing biography from prefs: aiName=${profile.aiName}',
            tag: 'ONBOARDING',
          );
        } on Exception catch (_) {}
      } else {
        _generatedBiography = null;
        _biographySaved = false;
      }
    } on Exception catch (e) {
      Log.e(
        'OnboardingLifecycle: failed to load existing biography: $e',
        tag: 'ONBOARDING',
      );
      _generatedBiography = null;
      _biographySaved = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Generate and save biography delegating to use case. Exposes importError on failure.
  Future<void> generateAndSaveBiography({
    required final BuildContext context,
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
    final Map<String, dynamic>? appearance,
    final void Function(String)? onProgress,
  }) async {
    _biographySaved = false;
    try {
      // Map the BiographyGenerationStep enum emitted by the use case to the
      // short keys expected by the UI's initializing screen (e.g. 'appearance',
      // 'avatar', 'finalize'). This ensures the screen's Completers complete
      // and the flow can proceed to the chat screen.
      String mapStepToKey(final BiographyGenerationStep step) {
        switch (step) {
          case BiographyGenerationStep.generatingBiography:
            return 'generating_basic';
          case BiographyGenerationStep.generatingAppearance:
            return 'appearance';
          case BiographyGenerationStep.generatingAvatar:
            return 'avatar';
          case BiographyGenerationStep.finalizing:
            return 'finalize';
          case BiographyGenerationStep.saving:
            return 'finish';
          case BiographyGenerationStep.completed:
            return 'finalize';
          case BiographyGenerationStep.error:
            return 'finalize';
        }
      }

      final finalBiography = await _biographyUseCase.generateCompleteBiography(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
        onProgress: (final step) {
          final mapped = mapStepToKey(step);
          Log.d(
            '[OnboardingLifecycle] usecase emitted step=$step mapped="$mapped"',
          );
          onProgress?.call(mapped);
        },
      );

      _generatedBiography = finalBiography;
      _biographySaved = true;
      importError = null;
      Log.i(
        'OnboardingLifecycle: biography generated for aiName=${finalBiography.aiName}',
      );
      notifyListeners();
    } on Exception catch (e) {
      _biographySaved = false;
      importError = e.toString();
      Log.e(
        'OnboardingLifecycle: error generating biography: $e',
        tag: 'ONBOARDING',
        error: e,
      );
      notifyListeners();
    }
  }

  Future<void> applyChatExport(final ChatExport exported) async {
    await _chatRepository.saveAll(exported.toJson());
    _generatedBiography = exported.profile;
    _biographySaved = true;
    notifyListeners();
  }

  void setImportError(final String? e) {
    importError = e;
    notifyListeners();
  }

  /// Reset lifecycle state and clear persisted biography via use case
  Future<void> reset() async {
    _generatedBiography = null;
    _biographySaved = false;
    try {
      await _biographyUseCase.clearSavedBiography();
    } on Exception catch (e) {
      Log.w('Error clearing saved biography in lifecycle reset: $e');
    }
    notifyListeners();
  }
}
