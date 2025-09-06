import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/import_export_onboarding_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/save_imported_chat_use_case.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

// Deprecated placeholder of original OnboardingProvider kept for history
class OnboardingProviderDeprecated extends ChangeNotifier {
  bool loadingStory = false;
  DateTime? userBirthdate;
  final BiographyGenerationUseCase _biographyUseCase;
  final ImportExportOnboardingUseCase _importExportUseCase;
  final SaveImportedChatUseCase _saveImportedChatUseCase;

  OnboardingProviderDeprecated({
    BiographyGenerationUseCase? biographyUseCase,
    ImportExportOnboardingUseCase? importExportUseCase,
    SaveImportedChatUseCase? saveImportedChatUseCase,
  }) : _biographyUseCase = biographyUseCase ?? BiographyGenerationUseCase(),
       _importExportUseCase =
           importExportUseCase ?? ImportExportOnboardingUseCase(),
       _saveImportedChatUseCase =
           saveImportedChatUseCase ?? SaveImportedChatUseCase() {
    // Initialize form key to avoid duplicate GlobalKey errors
    formKey = GlobalKey<FormState>();
    // Inicialización asíncrona que carga datos guardados y actualiza `loading`
    _loadBiographyFromStorage();
  }
  bool loading = true;

  /// Aplica un `ImportedChat` ya parseado al provider y lo persiste.
  Future<void> applyImportedChat(ImportedChat imported) async {
    await _saveImportedChatUseCase.saveImportedChat(imported);
    _generatedBiography = imported.profile;
    _biographySaved = true;
    notifyListeners();
  }

  /// Setea un mensaje de error de importación y notifica listeners.
  void setImportError(String? err) {
    importError = err;
    notifyListeners();
  }

  /// Resetea el estado interno tras borrar la caché
  void reset() {
    _generatedBiography = null;
    _biographySaved = false;

    // También limpiar SharedPreferences para evitar que _loadBiographyFromPrefs
    // encuentre datos viejos en el próximo reinicio
    _clearPrefsData();

    notifyListeners();
  }

  /// Limpia los datos de SharedPreferences de forma asíncrona
  void _clearPrefsData() async {
    try {
      await _biographyUseCase.clearSavedBiography();
    } catch (e) {
      Log.w('Error limpiando almacenamiento en reset(): $e');
    }
  }

  // Carga inicial desde SharedPreferences (sin UI) para tests y arranque
  Future<void> _loadBiographyFromStorage() async {
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

  AiChanProfile? _generatedBiography;
  bool _biographySaved = false;
  bool get biographySaved => _biographySaved;
  AiChanProfile? get generatedBiography => _generatedBiography;

  /// Genera la biografía, la guarda en caché y notifica a la UI
  /// [onProgress] recibe claves de progreso que pueden mapearse a pasos UI.
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
      onProgress?.call('start');
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
      notifyListeners();
    } catch (e) {
      _biographySaved = false;
      // Exponer error a la UI; dejar que la UI muestre el diálogo si es necesario
      importError = e.toString();
      notifyListeners();
    }
  }

  // Form controllers - initialized in constructor to avoid duplicate keys
  late final GlobalKey<FormState> formKey;
  final userNameController = TextEditingController();
  TextEditingController? aiNameController;
  final meetStoryController = TextEditingController();
  final birthDateController = TextEditingController();

  // Países seleccionados en onboarding
  String? userCountryCode;
  String? aiCountryCode;

  String get userName => userNameController.text;
  String? importError;

  // Las sugerencias ahora provienen dinámicamente de FemaleNamesRepo.forCountry

  void setAiNameController(TextEditingController controller) {
    aiNameController = controller;
  }

  void disposeControllers() {
    userNameController.dispose();
    aiNameController?.dispose();
    meetStoryController.dispose();
    birthDateController.dispose();
  }

  void setUserName(String value) {
    userNameController.text = value;
  }

  void setAiName(String value) {
    if (aiNameController != null && aiNameController!.text != value) {
      aiNameController!.text = value;
      Log.i(
        'setAiName: aiNameController.text forzado a: "$value"',
        tag: 'ONBOARD',
      );
    }
    // notifyListeners(); // Solo si necesitas refresco inmediato en la UI
  }

  void setUserBirthdate(DateTime? value) {
    userBirthdate = value;
    if (value != null) {
      birthDateController.text = '${value.day}/${value.month}/${value.year}';
    } else {
      birthDateController.text = '';
    }
  }

  void setMeetStory(String value) {
    // Solo actualizar si el valor es diferente para evitar mover el cursor
    if (meetStoryController.text != value) {
      meetStoryController.text = value;
    }
  }

  void setUserCountryCode(String value) {
    userCountryCode = value.trim().toUpperCase();
    notifyListeners();
  }

  void setAiCountryCode(String value) {
    aiCountryCode = value.trim().toUpperCase();
    notifyListeners();
  }

  void setLoadingStory(bool value) {
    loadingStory = value;
    notifyListeners();
  }

  Future<void> pickBirthDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: userBirthdate ?? DateTime(now.year - 25),
      firstDate: DateTime(1950),
      lastDate: now,
      locale: const Locale('es'),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.pinkAccent,
            surface: Colors.black,
            onSurface: Colors.pinkAccent,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
        ),
        child: child!,
      ),
    );
    if (picked != null) setUserBirthdate(picked);
  }

  Future<void> suggestStory(BuildContext context) async {
    if (userNameController.text.isNotEmpty &&
        aiNameController?.text.isNotEmpty == true) {
      setLoadingStory(true);
      meetStoryController.text = 'Generando historia...';

      try {
        final storyText = await OnboardingUtils.generateMeetStoryFromContext(
          userName: userNameController.text,
          aiName: aiNameController?.text ?? '',
          userCountry: userCountryCode,
          aiCountry: aiCountryCode,
          userBirthdate: userBirthdate,
        );

        if (!context.mounted) return;

        if (storyText.toLowerCase().contains('error al conectar con la ia') ||
            storyText.toLowerCase().contains('"error"')) {
          importError = storyText;
          meetStoryController.text = '';
          notifyListeners();
        } else {
          meetStoryController.text = storyText.trim();
        }
      } catch (e) {
        if (!context.mounted) return;
        meetStoryController.text = '';
        importError = e.toString();
        notifyListeners();
      } finally {
        setLoadingStory(false);
      }
    } else {}
  }

  Future<void> handleImportBiography(
    BuildContext context,
    Future<void> Function(ImportedChat importedChat)? onImportJson,
  ) async {
    // Delegate to use case which encapsulates file interactions and parsing
    try {
      final result = await _importExportUseCase.importFromJson();
      if (result.isSuccess && result.data != null && onImportJson != null) {
        await onImportJson(result.data!);
      } else if (result.hasError) {
        importError = result.error;
        notifyListeners();
      }
    } catch (e) {
      importError = e.toString();
      notifyListeners();
    }
  }

  void clearImportError() {
    importError = null;
    notifyListeners();
  }
}
