import 'package:ai_chan/models/system_prompt.dart';
import 'package:ai_chan/utils/storage_utils.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/services/ia_appearance_generator.dart';
import 'package:ai_chan/main.dart' show navigatorKey;
import 'package:ai_chan/utils/onboarding_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/ai_service.dart';
import '../utils/dialog_utils.dart';
import '../utils/chat_json_utils.dart' as chat_json_utils;
import '../models/imported_chat.dart';

class OnboardingProvider extends ChangeNotifier {
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

  // Inicialización automática desde SharedPreferences
  OnboardingProvider() {
    _loadBiographyFromPrefs();
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
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
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
    Map<String, dynamic>? appearance,
  }) async {
    _biographySaved = false;
    try {
      final biography = await generateFullBiographyFlexible(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        appearanceGenerator: IAAppearanceGenerator(),
      );
      if (!context.mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final jsonBio = jsonEncode(biography.toJson());
      await prefs.setString('onboarding_data', jsonBio);
      _generatedBiography = biography;
      _biographySaved = true;
    } catch (e) {
      _biographySaved = false;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al crear biografía'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  final formKey = GlobalKey<FormState>();
  final userNameController = TextEditingController();
  TextEditingController? aiNameController;
  final meetStoryController = TextEditingController();
  final birthDateController = TextEditingController();

  String get userName => userNameController.text;
  String get aiName => aiNameController?.text ?? '';
  DateTime? userBirthday;
  bool loadingStory = false;
  String? importError;

  // Sugerencias de nombres AI
  final List<String> aiNameSuggestions = [
    "Ai",
    "Aiko",
    "Airi",
    "Akane",
    "Akari",
    "Akemi",
    "Ami",
    "Asuka",
    "Atsuko",
    "Ayaka",
    "Ayane",
    "Ayano",
    "Ayumi",
    "Azusa",
    "Chie",
    "Chihiro",
    "Chika",
    "Chinatsu",
    "Chisato",
    "Chiyo",
    "Eiko",
    "Emi",
    "Ena",
    "Eri",
    "Erika",
    "Fumika",
    "Fumino",
    "Fuyuka",
    "Fuyumi",
    "Hana",
    "Hanae",
    "Hanako",
    "Haruka",
    "Harumi",
    "Haruna",
    "Hatsune",
    "Hazuki",
    "Hibiki",
    "Hikari",
    "Himari",
    "Hinako",
    "Hinata",
    "Hisako",
    "Hiyori",
    "Honoka",
    "Hotaru",
    "Ibuki",
    "Izumi",
    "Jun",
    "Junko",
    "Kaho",
    "Kana",
    "Kanae",
    "Kanako",
    "Kanna",
    "Kanon",
    "Kaori",
    "Kasumi",
    "Katsumi",
    "Kayo",
    "Kazue",
    "Kazuko",
    "Kazumi",
    "Kei",
    "Keiko",
    "Kikue",
    "Kiyomi",
    "Koharu",
    "Kokoro",
    "Kotone",
    "Kumi",
    "Kumiko",
    "Kurumi",
    "Kyoko",
    "Madoka",
    "Mai",
    "Maiko",
    "Maki",
    "Makoto",
    "Mami",
    "Mana",
    "Manami",
    "Mariko",
    "Marina",
    "Masami",
    "Masumi",
    "Matsuri",
    "Mayu",
    "Mayuko",
    "Mayumi",
    "Megu",
    "Megumi",
    "Mei",
    "Mie",
    "Mieko",
    "Miharu",
    "Miho",
    "Mika",
    "Mikako",
    "Miki",
    "Miku",
    "Mina",
    "Minami",
    "Minori",
    "Mio",
    "Misaki",
    "Misato",
    "Mitsue",
    "Mitsuki",
    "Mitsuko",
    "Mitsuru",
    "Miyako",
    "Miyu",
    "Mizue",
    "Mizuki",
    "Momoka",
    "Momoko",
    "Mutsumi",
    "Naho",
    "Namie",
    "Nana",
    "Nanami",
    "Nao",
    "Naoko",
    "Narumi",
    "Natsue",
    "Natsuki",
    "Natsuko",
    "Natsumi",
    "Noa",
    "Nobuko",
    "Noriko",
    "Nozomi",
    "Rei",
    "Reika",
    "Reiko",
    "Reina",
    "Remi",
    "Rena",
    "Rie",
    "Rika",
    "Riko",
    "Rin",
    "Rina",
    "Rio",
    "Risa",
    "Risako",
    "Rui",
    "Rumi",
    "Rumiko",
    "Ruri",
    "Ryoko",
    "Sachie",
    "Sachiko",
    "Sae",
    "Saki",
    "Sakura",
    "Sana",
    "Sanae",
    "Satoko",
    "Satomi",
    "Sayaka",
    "Sayuri",
    "Seina",
    "Setsuko",
    "Shigeko",
    "Shiori",
    "Shizue",
    "Shizuka",
    "Shoko",
    "Sora",
    "Sumiko",
    "Sumire",
    "Suzuka",
    "Suzume",
    "Takako",
    "Takara",
    "Tama",
    "Tamaki",
    "Tamami",
    "Terumi",
    "Tokiko",
    "Tomoe",
    "Tomoka",
    "Tomomi",
    "Toyoko",
    "Tsukasa",
    "Tsukiko",
    "Tsukushi",
    "Umeko",
    "Umika",
    "Wakana",
    "Yae",
    "Yasuko",
    "Yayoi",
    "Yoko",
    "Yoshie",
    "Yoshiko",
    "Yoshimi",
    "Yoshino",
    "Yui",
    "Yuina",
    "Yuka",
    "Yukae",
    "Yukari",
    "Yuki",
    "Yukie",
    "Yukiko",
    "Yukina",
    "Yume",
    "Yumeka",
    "Yumena",
    "Yumiko",
    "Yumina",
    "Yuna",
    "Yuri",
    "Yurika",
    "Yuriko",
    "Yurina",
    "Yuu",
    "Yuuka",
    "Yuuko",
    "Yuuri",
    "Yuzu",
    "Yuzuka",
    "Yuzuki",
    "Yuzumi",
    "Yuzuna",
    "Yuzuno",
    "Yuzusa",
  ];

  Iterable<String> aiNameOptionsBuilder(TextEditingValue textEditingValue) {
    if (textEditingValue.text == '') {
      return const Iterable<String>.empty();
    }
    return aiNameSuggestions.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
  }

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
      debugPrint('[LOG setAiName] aiNameController.text forzado a: "$value"');
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
    if (userNameController.text.isNotEmpty && aiNameController?.text.isNotEmpty == true) {
      setLoadingStory(true);
      meetStoryController.text = "Generando historia...";
      final prompt =
          "Inventa una breve historia romántica y realista de cómo se conocieron "
          "${userNameController.text} y ${aiNameController?.text}. La chica vive en una dimensión paralela de la Tierra, idéntica a la nuestra pero separada por una barrera tecnológica. Su existencia es digital, como en Matrix, pero nunca lo admite ni lo menciona al usuario. Solo puede comunicarse por chat y llamada, pero sueña con que algún día podrán verse gracias a la realidad aumentada. Hazlo creíble y simpático, como el inicio de una relación real, en 3-5 frases. La chica es japonesa y se conocieron online, probablemente en alguna comunidad otaku o friki. Al final de la historia, ambos se intercambian sus datos de contacto y acuerdan empezar a hablar por primera vez, pero aún no han tenido ninguna conversación privada. No menciones plataformas concretas (como Discord, WhatsApp, Telegram, etc.), ni detalles sobre conversaciones previas, solo que han decidido empezar a hablar. Añade que la chica espera con ilusión el primer mensaje del usuario.";

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
          personality: {},
          appearance: {},
        ),
        dateTime: DateTime.now(),
        instructions: instrucciones,
      );
      try {
        final story = await AIService.sendMessage(
          [
            {"role": "user", "content": prompt, "datetime": DateTime.now().toIso8601String()},
          ],
          systemPromptObj,
          model: 'gemini-2.5-flash',
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
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
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
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
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
