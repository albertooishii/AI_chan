import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/onboarding/presentation/screens/onboarding_mode_selector.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:ai_chan/chat/infrastructure/services/prompt_builder_service.dart';

import 'package:ai_chan/chat.dart';
import 'dart:convert';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'core/di.dart' as di;
import 'core/di_bootstrap.dart' as di_bootstrap;
import 'package:ai_chan/chat/application/utils/profile_persist_utils.dart' as profile_persist_utils;
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_chan/shared/services/firebase_init.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.initialize();

  // Initialize Firebase early so adapters using FirebaseAuth can work.
  // Use the helper that tries native init first and falls back to parsing
  // google-services.json when necessary. Retry a few times to surface
  // intermittent initialization race conditions.
  // Initialize Firebase (automatically disabled on desktop platforms)
  final firebaseReady = await ensureFirebaseInitialized();
  if (!firebaseReady) {
    debugPrint('firebase_init: Firebase not available on this platform');
  } else {
    debugPrint('firebase_init: Firebase initialized successfully');
  }

  di_bootstrap.registerDefaultRealtimeClientFactories();

  await PrefsUtils.ensureDefaults();

  runApp(const RootApp());
}

class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  late final OnboardingProvider _onboardingProvider;

  @override
  void initState() {
    super.initState();
    _onboardingProvider = OnboardingProvider();
  }

  @override
  void dispose() {
    try {
      _onboardingProvider.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _onboardingProvider,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: Config.getAppName(),
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pinkAccent, brightness: Brightness.dark),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: MyApp(onboardingProvider: _onboardingProvider),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  final OnboardingProvider onboardingProvider;
  const MyApp({super.key, required this.onboardingProvider});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ChatProvider? _chatProvider;
  Future<void> resetApp() async {
    Log.i('resetApp llamado');

    // Debug: estado antes del reset
    Log.d(
      'resetApp ANTES: generatedBiography=${widget.onboardingProvider.generatedBiography?.aiName}, biographySaved=${widget.onboardingProvider.biographySaved}',
    );

    try {
      // Limpieza unificada y simplificada: una sola llamada que lo borra TODO
      await AppDataUtils.clearAllAppData();
      Log.d('resetApp: Todos los datos limpiados');

      // Limpiar estado en memoria de los providers
      if (_chatProvider != null) {
        _chatProvider!.messages.clear();
        // Crear perfil vacío en memoria sin persistir
        _chatProvider!.onboardingData = AiChanProfile(
          userName: '',
          aiName: '',
          userBirthdate: DateTime.now(),
          aiBirthdate: DateTime.now(),
          biography: {},
          appearance: {},
          timeline: [],
        );
      }

      // Resetear provider OnboardingProvider usando método público reset()
      widget.onboardingProvider.reset();

      // Limpiar controladores de texto manualmente
      widget.onboardingProvider.userNameController.clear();
      widget.onboardingProvider.aiNameController?.clear();
      widget.onboardingProvider.meetStoryController.clear();
      widget.onboardingProvider.birthDateController.clear();
      widget.onboardingProvider.userCountryCode = null;
      widget.onboardingProvider.aiCountryCode = null;
      widget.onboardingProvider.userBirthdate = null;

      // Nullificar ChatProvider para forzar recreación limpia
      _chatProvider = null;

      // Debug: estado después del reset
      Log.d(
        'resetApp DESPUÉS: generatedBiography=${widget.onboardingProvider.generatedBiography?.aiName}, biographySaved=${widget.onboardingProvider.biographySaved}',
      );

      Log.i('resetApp completado exitosamente');
    } catch (e) {
      Log.e('Error en resetApp: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      try {
        if (!kIsWeb && Platform.isAndroid) {
          await Future.delayed(const Duration(milliseconds: 500));
          await Permission.storage.request();
        }
      } catch (e) {
        Log.e('Error solicitando permisos de almacenamiento', tag: 'PERM', error: e);
      }
      setState(() {
        _initialized = true;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      _chatProvider?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CyberpunkLoader(message: 'BOOTING SYSTEM...', showProgressBar: true)),
      );
    }

    final onboardingProvider = widget.onboardingProvider;
    if (onboardingProvider.loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CyberpunkLoader(message: 'LOADING USER DATA...', showProgressBar: true)),
      );
    }

    if (!onboardingProvider.biographySaved) {
      return OnboardingModeSelector(
        onFinish:
            ({
              required String userName,
              required String aiName,
              required DateTime? userBirthdate,
              required String meetStory,
              String? userCountryCode,
              String? aiCountryCode,
              Map<String, dynamic>? appearance,
            }) async {
              final navigator = Navigator.of(context);
              onboardingProvider.setUserName(userName);
              onboardingProvider.setAiName(aiName);
              await navigator.push<AiChanProfile>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => InitializingScreen(
                    bioFutureFactory: ([void Function(String)? onProgress]) async {
                      await onboardingProvider.generateAndSaveBiography(
                        context: context,
                        userName: userName,
                        aiName: aiName,
                        userBirthdate: userBirthdate,
                        meetStory: meetStory,
                        userCountryCode: userCountryCode,
                        aiCountryCode: aiCountryCode,
                        appearance: appearance,
                        onProgress: onProgress,
                      );
                      if (onboardingProvider.generatedBiography == null) {
                        throw Exception('No se pudo generar la biografía');
                      }
                      return onboardingProvider.generatedBiography!;
                    },
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
        onClearAllDebug: resetApp,
        onImportJson: (importedChat) async {
          final jsonStr = jsonEncode(importedChat.toJson());
          final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
            jsonStr,
            onError: (err) => onboardingProvider.setImportError(err),
          );
          if (imported != null) {
            await onboardingProvider.applyImportedChat(imported);
            if (mounted) setState(() {});
          }
        },
        onboardingProvider: onboardingProvider,
      );
    }

    // Ensure we only create the ChatProvider once and pass it down explicitly
    if (_chatProvider == null) {
      Log.i('MAIN: Creando nuevo ChatProvider');
      final repo = di.getChatRepository();
      _chatProvider = ChatProvider(repository: repo, promptBuilderService: PromptBuilderService());

      // Solo persistir datos si realmente hay una biografía válida Y los datos están guardados
      // Esto evita que se persistan datos fantasma después de un resetApp()
      if (onboardingProvider.generatedBiography != null && onboardingProvider.biographySaved) {
        Log.i('MAIN: Persistiendo biografía: ${onboardingProvider.generatedBiography!.aiName}');
        profile_persist_utils.setOnboardingDataAndPersist(_chatProvider!, onboardingProvider.generatedBiography!);
      } else {
        Log.i(
          'MAIN: NO persistiendo biografía (generatedBiography=${onboardingProvider.generatedBiography?.aiName}, biographySaved=${onboardingProvider.biographySaved})',
        );
      }

      Log.i('MAIN: Llamando loadAll()');
      _chatProvider!.loadAll();
    } else {
      Log.i('MAIN: Reutilizando ChatProvider existente');
    }

    return ChangeNotifierProvider.value(
      value: _chatProvider!,
      child: ChatScreen(
        bio: onboardingProvider.generatedBiography!,
        aiName: onboardingProvider.generatedBiography!.aiName,
        chatProvider: _chatProvider!,
        onClearAllDebug: resetApp,
        onImportJson: (importedChat) async {
          final ob = onboardingProvider;
          final jsonStr = jsonEncode(importedChat.toJson());
          final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
            jsonStr,
            onError: (err) => ob.setImportError(err),
          );
          if (imported != null) {
            await ob.applyImportedChat(imported);
          }
        },
      ),
    );
  }
}
