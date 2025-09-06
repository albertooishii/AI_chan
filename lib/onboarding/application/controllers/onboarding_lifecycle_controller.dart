import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/import_export_onboarding_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/save_imported_chat_use_case.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Lifecycle controller that owns onboarding lifecycle state (biography loading,
/// saved/generated biography, import errors). This intentionally does NOT own
/// form controllers — those live in `FormOnboardingController`.
class OnboardingLifecycleController extends ChangeNotifier {
  final BiographyGenerationUseCase _biographyUseCase;
  final SaveImportedChatUseCase _saveImportedChatUseCase;

  bool loading = true;
  AiChanProfile? _generatedBiography;
  bool _biographySaved = false;
  String? importError;

  OnboardingLifecycleController({
    BiographyGenerationUseCase? biographyUseCase,
    ImportExportOnboardingUseCase? importExportUseCase,
    SaveImportedChatUseCase? saveImportedChatUseCase,
  }) : _biographyUseCase = biographyUseCase ?? BiographyGenerationUseCase(),
       _saveImportedChatUseCase =
           saveImportedChatUseCase ?? SaveImportedChatUseCase() {
    _loadExistingBiography();
  }

  AiChanProfile? get generatedBiography => _generatedBiography;
  bool get biographySaved => _biographySaved;

  Future<void> _loadExistingBiography() async {
    try {
      final profile = await _biographyUseCase.loadExistingBiography();
      if (profile != null) {
        _generatedBiography = profile;
        _biographySaved = true;
      } else {
        _generatedBiography = null;
        _biographySaved = false;
      }
    } catch (e) {
      _generatedBiography = null;
      _biographySaved = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Generate and save biography delegating to use case. Exposes importError on failure.
  Future<void> generateAndSaveBiography({
    required BuildContext context,
    required String userName,
    required String aiName,
    required DateTime? userBirthdate,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    Map<String, dynamic>? appearance,
    void Function(String)? onProgress,
  }) async {
    _biographySaved = false;
    try {
      final finalBiography = await _biographyUseCase.generateCompleteBiography(
        userName: userName,
        aiName: aiName,
        userBirthdate: userBirthdate,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
        onProgress: (step) => onProgress?.call(step.toString()),
      );

      _generatedBiography = finalBiography;
      _biographySaved = true;
      importError = null;
      notifyListeners();
    } catch (e) {
      _biographySaved = false;
      importError = e.toString();
      notifyListeners();
    }
  }

  Future<void> applyImportedChat(ImportedChat imported) async {
    await _saveImportedChatUseCase.saveImportedChat(imported);
    _generatedBiography = imported.profile;
    _biographySaved = true;
    notifyListeners();
  }

  void setImportError(String? e) {
    importError = e;
    notifyListeners();
  }

  /// Reset lifecycle state and clear persisted biography via use case
  Future<void> reset() async {
    _generatedBiography = null;
    _biographySaved = false;
    try {
      await _biographyUseCase.clearSavedBiography();
    } catch (e) {
      Log.w('Error clearing saved biography in lifecycle reset: $e');
    }
    notifyListeners();
  }
}
