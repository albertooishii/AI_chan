import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/utils/provider_persist_utils.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'dart:convert';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/utils/log_utils.dart';

class OnboardingProvider extends ChangeNotifier {
  bool loadingStory = false;
  DateTime? userBirthday;
  final IProfileService _profileService = di.getProfileServiceForProvider();
  final Future<String?> Function(String base64, {String prefix})?
  saveImageFunc = null;

  OnboardingProvider() {
    // Inicialización asíncrona que carga datos guardados y actualiza `loading`
    _loadBiographyFromPrefs();
  }
  bool loading = true;

  /// Aplica un `ImportedChat` ya parseado al provider y lo persiste.
  Future<void> applyImportedChat(ImportedChat imported) async {
    await ProviderPersistUtils.saveImportedChat(imported);
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
      await PrefsUtils.removeOnboardingData();
      await PrefsUtils.removeChatHistory();
    } catch (e) {
      Log.w('Error limpiando SharedPreferences en reset(): $e');
    }
  }

  // Carga inicial desde SharedPreferences (sin UI) para tests y arranque
  Future<void> _loadBiographyFromPrefs() async {
    try {
      // Use centralized StorageUtils to load imported chat (keeps format stable)
      final jsonStr = await PrefsUtils.getOnboardingData();
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        final profile = await AiChanProfile.tryFromJson(json);
        if (profile != null) {
          _generatedBiography = profile;
          _biographySaved = true;
        } else {
          _generatedBiography = null;
          _biographySaved = false;
        }
      } else {
        _generatedBiography = null;
        _biographySaved = false;
      }
    } catch (e) {
      // En tests/entorno sin UI no mostramos diálogos; limpiamos prefs si hay corrupción
      try {
        await PrefsUtils.removeOnboardingData();
        await PrefsUtils.removeChatHistory();
      } catch (_) {}
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
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    Map<String, dynamic>? appearance,
    void Function(String)? onProgress,
  }) async {
    _biographySaved = false;
    try {
      onProgress?.call('start');
      final biography = await _profileService.generateBiography(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
      onProgress?.call('generating_basic');
      // Generar apariencia y avatar
      // Señalizamos el inicio de la generación de apariencia (índice 12)
      onProgress?.call('appearance');
      final appearanceMap = await IAAppearanceGenerator()
          .generateAppearanceFromBiography(biography);
      // Señalizamos la fase de estilo de apariencia (índice 13)
      onProgress?.call('style');
      // Preparar fases de generación de avatar: 'avatar' (índice 14)
      // y 'finish' (índice 15) se emitirán antes de la llamada al generador
      // para que ambos pasos se muestren durante la generación del avatar.
      onProgress?.call('avatar');
      onProgress?.call('finish');
      // Generate avatar (replace existing) and attach to biography
      final updatedBiography = biography.copyWith(appearance: appearanceMap);
      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
        updatedBiography,
      );
      final biographyWithAvatar = updatedBiography.copyWith(avatars: [avatar]);
      // Tras completarse la creación del avatar, emitir 'finalize' (índice 16)
      // y mantener ese estado visible unos segundos para la transición UX.
      onProgress?.call('finalize');
      // Dejar la pantalla en el estado final unos segundos para que el usuario
      // aprecie el paso 16 antes de persistir/navegar.
      await Future.delayed(const Duration(seconds: 3));
      // Persistir siempre en SharedPreferences aunque el contexto UI haya sido desmontado.
      final jsonBio = jsonEncode(biographyWithAvatar.toJson());
      await PrefsUtils.setOnboardingData(jsonBio);
      _generatedBiography = biographyWithAvatar;
      _biographySaved = true;
      // Notificar listeners (si los hay). Mostrar diálogos UI solo si el context está montado.
      notifyListeners();
    } catch (e) {
      _biographySaved = false;
      if (!context.mounted) return;
      await showAppDialog(
        builder: (ctx) => AlertDialog(
          title: const Text('Error al crear biografía'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  final formKey = GlobalKey<FormState>();
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

  void setUserBirthday(DateTime? value) {
    userBirthday = value;
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
      initialDate: userBirthday ?? DateTime(now.year - 25),
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
    if (picked != null) setUserBirthday(picked);
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
          userBirthday: userBirthday,
        );

        if (!context.mounted) return;

        if (storyText.toLowerCase().contains('error al conectar con la ia') ||
            storyText.toLowerCase().contains('"error"')) {
          await showErrorDialog(storyText);
          meetStoryController.text = '';
        } else {
          meetStoryController.text = storyText.trim();
        }
      } catch (e) {
        if (!context.mounted) return;
        meetStoryController.text = '';
        await showErrorDialog(e.toString());
      } finally {
        setLoadingStory(false);
      }
    } else {}
  }

  Future<void> handleImportBiography(
    BuildContext context,
    Future<void> Function(ImportedChat importedChat)? onImportJson,
  ) async {
    final result = await chat_json_utils.ChatJsonUtils.importJsonFile();
    if (!context.mounted) return;
    final String? jsonStr = result.$1;
    final String? error = result.$2;
    if (!context.mounted) return;
    if (error != null) {
      await showAppDialog(
        builder: (ctx) => AlertDialog(
          title: const Text('Error al leer archivo'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (jsonStr != null && jsonStr.trim().isNotEmpty && onImportJson != null) {
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) {
          importError = err;
          notifyListeners();
        },
      );
      if (importError != null || imported == null) {
        if (!context.mounted) return;
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            title: const Text('Error al importar'),
            content: Text(importError ?? 'Error desconocido al importar JSON'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      await onImportJson(imported);
    }
  }

  void clearImportError() {
    importError = null;
    notifyListeners();
  }
}
