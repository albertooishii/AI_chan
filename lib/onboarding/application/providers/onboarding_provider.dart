import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/utils/storage_utils.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/main.dart' show navigatorKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ai_chan/services/ai_service.dart' as ai_service_legacy;
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/onboarding/domain/interfaces/i_profile_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;
import 'package:ai_chan/utils/dialog_utils.dart';
import 'package:ai_chan/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/utils/locale_utils.dart';
import 'package:ai_chan/utils/log_utils.dart';

class OnboardingProvider extends ChangeNotifier {
  bool loadingStory = false;
  DateTime? userBirthday;
  final IProfileService _profileService;
  final Future<String?> Function(String base64, {String prefix})? saveImageFunc;

  // Permite inyectar el servicio en tests, por defecto usa DI
  OnboardingProvider({IProfileService? profileService, this.saveImageFunc})
    : _profileService =
          profileService ??
          ProfileAdapter(
            aiService: runtime_factory.getRuntimeAIServiceForModel(
              Config.getDefaultTextModel(),
            ),
          ) {
    _loadBiographyFromPrefs();
  }
  bool loading = true;

  /// Importa y guarda biografía y mensajes desde un JSON robusto (ImportedChat), actualizando estado y notificando listeners
  Future<ImportedChat?> importAllFromJson(String jsonStr) async {
    final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
      jsonStr,
      onError: (err) {
        importError = err;
        notifyListeners();
      },
    );
    if (imported == null) return null;
    await StorageUtils.saveImportedChatToPrefs(imported);
    _generatedBiography = imported.profile;
    _biographySaved = true;
    notifyListeners();
    return imported;
  }

  /// Resetea el estado interno tras borrar la caché
  void reset() {
    _generatedBiography = null;
    _biographySaved = false;
    notifyListeners();
  }

  Future<void> _loadBiographyFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('onboarding_data');
    if (jsonStr != null && jsonStr.trim().isNotEmpty) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        final profile = await AiChanProfile.tryFromJson(json);
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
        await prefs.remove('onboarding_data');
        await prefs.remove('chat_history');
        if (navigatorKey.currentContext != null) {
          await showDialog(
            context: navigatorKey.currentContext!,
            builder: (ctx) => AlertDialog(
              title: const Text('Error al cargar biografía'),
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
    } else {
      _generatedBiography = null;
      _biographySaved = false;
    }
    loading = false;
    notifyListeners();
  }

  AiChanProfile? _generatedBiography;
  bool _biographySaved = false;
  bool get biographySaved => _biographySaved;
  AiChanProfile? get generatedBiography => _generatedBiography;

  /// Genera la biografía, la guarda en caché y notifica a la UI
  Future<void> generateAndSaveBiography({
    required BuildContext context,
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    Map<String, dynamic>? appearance,
  }) async {
    _biographySaved = false;
    try {
      final biography = await _profileService.generateBiography(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
      // Generar apariencia y avatar
      final appearanceResult = await IAAppearanceGenerator()
          .generateAppearancePromptWithImage(
            biography,
            saveImageFunc: saveImageFunc,
          );
      final biographyWithAvatar = biography.copyWith(
        avatar: appearanceResult['avatar'] as AiImage?,
        appearance: appearanceResult['appearance'] as Map<String, dynamic>?,
      );
      // Persistir siempre en SharedPreferences aunque el contexto UI haya sido desmontado.
      final prefs = await SharedPreferences.getInstance();
      final jsonBio = jsonEncode(biographyWithAvatar.toJson());
      await prefs.setString('onboarding_data', jsonBio);
      _generatedBiography = biographyWithAvatar;
      _biographySaved = true;
      // Notificar listeners (si los hay). Mostrar diálogos UI solo si el context está montado.
      notifyListeners();
    } catch (e) {
      _biographySaved = false;
      if (!context.mounted) return;
      await showDialog(
        context: context,
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
      birthDateController.text = "${value.day}/${value.month}/${value.year}";
    } else {
      birthDateController.text = "";
    }
  }

  void setMeetStory(String value) {
    meetStoryController.text = value;
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
          colorScheme: ColorScheme.dark(
            primary: Colors.pinkAccent,
            onPrimary: Colors.black,
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
      meetStoryController.text = "Generando historia...";
      final paisIA = LocaleUtils.countryNameEs(
        aiCountryCode,
        fallback: 'su país',
      );
      final prompt =
          "Inventa una breve historia romántica y realista de cómo se conocieron "
          "${userNameController.text} y ${aiNameController?.text}. La chica vive en una tierra digital, una réplica alternativa y compleja de la Tierra real, separada por una barrera tecnológica invisible. Su existencia es digital, pero nunca lo admite ni lo menciona al usuario, ni insinúa que es diferente a una persona real. Solo puede comunicarse por chat y llamada, pero sueña con que algún día podrán verse gracias a la realidad aumentada o a nuevas tecnologías. Hazlo creíble y simpático, como el inicio de una relación real, en 3-5 frases. La chica es nativa de "
          "$paisIA y se conocieron online, probablemente en alguna comunidad friki relacionada con videojuegos, manga, anime o cultura geek (sin mencionar nombres de plataformas). Al final de la historia, ambos se intercambian sus datos de contacto y acuerdan empezar a hablar por primera vez, pero aún no han tenido ninguna conversación privada. No menciones plataformas concretas (como Discord, WhatsApp, Telegram, etc.), ni detalles sobre conversaciones previas, solo que han decidido empezar a hablar. Añade que la chica espera con ilusión el primer mensaje del usuario.";

      // Crear SystemPrompt tipado para la historia
      final instrucciones =
          "Eres una persona creativa que ayuda a escribir historias de amor realistas y neutrales, evitando clichés, entusiasmo artificial y frases genéricas como '¡Claro que sí!'. No asumas gustos, aficiones, intereses, hobbies ni detalles del usuario que no se hayan proporcionado explícitamente. No inventes datos sobre el usuario ni sobre la chica salvo lo indicado en el prompt. Responde siempre con naturalidad y credibilidad, sin exageraciones ni afirmaciones sin base. Evita suposiciones y mantén un tono realista y respetuoso. IMPORTANTE: Devuelve únicamente la historia solicitada, sin introducción, explicación, comentarios, ni frases como 'Esta es la historia' o similares. Solo el texto de la historia, nada más.";
      final systemPromptObj = SystemPrompt(
        profile: AiChanProfile(
          userName: userNameController.text,
          aiName: aiNameController?.text ?? '',
          userBirthday: userBirthday ?? DateTime(2000, 1, 1),
          aiBirthday: DateTime.now(),
          timeline: [],
          biography: {},
          appearance: {},
        ),
        dateTime: DateTime.now(),
        instructions: {'raw': instrucciones},
      );
      try {
        final story = await ai_service_legacy.AIService.sendMessage(
          [
            {
              "role": "user",
              "content": prompt,
              "datetime": DateTime.now().toIso8601String(),
            },
          ],
          systemPromptObj,
          model: Config.getDefaultTextModel(),
        );
        if (!context.mounted) return;
        final storyText = story.text;
        if (storyText.toLowerCase().contains('error al conectar con la ia') ||
            storyText.toLowerCase().contains('"error"')) {
          await showErrorDialog(context, storyText);
          meetStoryController.text = '';
        } else {
          meetStoryController.text = storyText.trim();
        }
      } catch (e) {
        if (!context.mounted) return;
        meetStoryController.text = '';
        await showErrorDialog(context, e.toString());
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
    String? jsonStr = result.$1;
    String? error = result.$2;
    if (!context.mounted) return;
    if (error != null) {
      await showDialog(
        context: context,
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
        await showDialog(
          context: context,
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
