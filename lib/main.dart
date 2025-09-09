import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart' as utils;
import 'package:ai_chan/shared/utils/log_utils.dart' as utils;
import 'package:ai_chan/shared/utils/app_data_utils.dart' as utils;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as utils;
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import 'package:ai_chan/chat.dart';
import 'dart:convert';
import 'core/di.dart' as di;
import 'core/di_bootstrap.dart' as di_bootstrap;
import 'package:ai_chan/shared/infrastructure/utils/profile_persist_utils.dart'
    as profile_persist_utils;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_chan/shared/services/firebase_init.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.initialize();

  // The new AIProviderManager system auto-initializes on first access
  utils.Log.i(
    'AI Provider system will initialize automatically on first use',
    tag: 'STARTUP',
  );

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

  await utils.PrefsUtils.ensureDefaults();

  // Debug: log onboarding data present at app start (helps verify persistence on cold start)
  try {
    final onboardingJson = await utils.PrefsUtils.getOnboardingData();
    if (onboardingJson != null && onboardingJson.trim().isNotEmpty) {
      utils.Log.i(
        'MAIN: onboarding_data present at startup: ${onboardingJson.substring(0, onboardingJson.length.clamp(0, 200))}...',
        tag: 'STARTUP',
      );
    } else {
      utils.Log.i('MAIN: no onboarding_data found at startup', tag: 'STARTUP');
    }
  } on Exception catch (e) {
    utils.Log.e(
      'MAIN: failed reading onboarding_data at startup: $e',
      tag: 'STARTUP',
    );
  }

  runApp(const RootApp());
}

class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  late final OnboardingLifecycleController _onboardingLifecycle;

  @override
  void initState() {
    super.initState();
    _onboardingLifecycle = OnboardingLifecycleController(
      chatRepository: di.getChatRepository(),
    );
  }

  @override
  void dispose() {
    try {
      _onboardingLifecycle.dispose();
    } on Exception catch (_) {}
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _onboardingLifecycle,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: Config.getAppName(),
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pinkAccent,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: MyApp(onboardingLifecycle: _onboardingLifecycle),
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
  const MyApp({super.key, required this.onboardingLifecycle});
  final OnboardingLifecycleController onboardingLifecycle;

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ChatController? _chatController; // ✅ DDD: ETAPA 3 - DDD puro
  Future<void> resetApp() async {
    utils.Log.i('resetApp llamado');

    // Debug: estado antes del reset
    utils.Log.d(
      'resetApp ANTES: generatedBiography=${widget.onboardingLifecycle.generatedBiography?.aiName}, biographySaved=${widget.onboardingLifecycle.biographySaved}',
    );

    try {
      // Limpieza unificada y simplificada: una sola llamada que lo borra TODO
      await utils.AppDataUtils.clearAllAppData();
      utils.Log.d('resetApp: Todos los datos limpiados');

      // Limpiar estado en memoria de los providers
      if (_chatController != null) {
        await _chatController!
            .clearMessages(); // ✅ DDD: ETAPA 3 - Usar método de ChatController
        // Crear perfil vacío en memoria sin persistir
        _chatController!.dataController.updateProfile(
          AiChanProfile(
            // ✅ DDD: ETAPA 3 - Usar updateProfile
            userName: '',
            aiName: '',
            userBirthdate: DateTime.now(),
            aiBirthdate: DateTime.now(),
            biography: {},
            appearance: {},
          ),
        ); // ✅ DDD: ETAPA 3 - Cerrar constructor AiChanProfile y updateProfile

        // Resetear provider OnboardingProvider usando método público reset()
        // Resetear lifecycle controller state
        await widget.onboardingLifecycle.reset();
      }

      // Nullificar ChatController para forzar recreación limpia
      _chatController = null; // ✅ DDD: ETAPA 3

      // Debug: estado después del reset
      utils.Log.d(
        'resetApp DESPUÉS: generatedBiography=${widget.onboardingLifecycle.generatedBiography?.aiName}, biographySaved=${widget.onboardingLifecycle.biographySaved}',
      );

      utils.Log.i('resetApp completado exitosamente');
    } on Exception catch (e) {
      utils.Log.e('Error en resetApp: $e');
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
      } on Exception catch (e) {
        utils.Log.e(
          'Error solicitando permisos de almacenamiento',
          tag: 'PERM',
          error: e,
        );
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
      _chatController?.dispose(); // ✅ DDD: ETAPA 3
    } on Exception catch (_) {}
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CyberpunkLoader(
            message: 'BOOTING SYSTEM...',
            showProgressBar: true,
          ),
        ),
      );
    }

    // Listen to the provider so UI rebuilds when lifecycle state changes
    final onboardingLifecycle = Provider.of<OnboardingLifecycleController>(
      context,
    );
    if (onboardingLifecycle.loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CyberpunkLoader(
            message: 'LOADING USER DATA...',
            showProgressBar: true,
          ),
        ),
      );
    }

    if (!onboardingLifecycle.biographySaved) {
      return OnboardingModeSelector(
        onFinish:
            ({
              required final String userName,
              required final String aiName,
              required final DateTime? userBirthdate,
              required final String meetStory,
              final String? userCountryCode,
              final String? aiCountryCode,
              final Map<String, dynamic>? appearance,
            }) async {
              // Use the global navigatorKey to obtain a NavigatorState safely.
              // Navigator.of(context) can be null or invalid if the captured
              // context is not mounted at callback time; using the global
              // navigator avoids Null check operator failures.
              final nav = navigatorKey.currentState;
              if (nav == null) {
                utils.Log.e(
                  'Navigator state is not available when finishing onboarding',
                );
                return;
              }

              // Lifecycle controller only owns lifecycle; form controllers will be
              // created by the onboarding screens. Use the lifecycle to generate
              // and persist the biography once the form finishes.
              final returned = await nav.push<AiChanProfile>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => InitializingScreen(
                    bioFutureFactory:
                        ([final void Function(String)? onProgress]) async {
                          await onboardingLifecycle.generateAndSaveBiography(
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
                          if (onboardingLifecycle.generatedBiography == null) {
                            throw Exception('No se pudo generar la biografía');
                          }
                          return onboardingLifecycle.generatedBiography!;
                        },
                  ),
                ),
              );

              // Log and ensure we navigate to Chat explicitly when the initializer
              // returns a generated profile. This avoids race conditions where the
              // UI rebuild path might still show onboarding.
              utils.Log.d(
                'MAIN: InitializingScreen returned: profile=${returned?.aiName} biographySaved=${onboardingLifecycle.biographySaved}',
              );

              if (returned != null) {
                // Ensure a ChatController exists and persist onboarding data as the
                // normal build path would do. Then navigate to ChatScreen replacing
                // the current onboarding route.
                if (_chatController == null) {
                  utils.Log.i(
                    'MAIN: Creando ChatController tras InitializingScreen',
                  );
                  _chatController = di.getChatController();
                }

                if (onboardingLifecycle.generatedBiography != null &&
                    onboardingLifecycle.biographySaved) {
                  utils.Log.i(
                    'MAIN: Persistiendo biografía tras InitializingScreen: ${onboardingLifecycle.generatedBiography!.aiName}',
                  );
                  // Esperar a que la persistencia complete antes de navegar al Chat
                  await profile_persist_utils.setOnboardingDataAndPersist(
                    onboardingLifecycle.generatedBiography!,
                  );

                  // Ensure the ChatController loads persisted data before showing Chat
                  try {
                    await _chatController!.initialize();
                  } on Exception catch (e) {
                    utils.Log.w('MAIN: ChatController.initialize() failed: $e');
                  }
                }

                // Replace the whole route stack with the ChatScreen so we never
                // return to onboarding screens after initialization completes.
                await nav.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: _chatController,
                      child: ChatScreen(
                        bio: onboardingLifecycle.generatedBiography!,
                        aiName: onboardingLifecycle.generatedBiography!.aiName,
                        chatController: _chatController!,
                        onClearAllDebug: resetApp,
                        onImportJson: (final importedChat) async {
                          final ob = onboardingLifecycle;
                          final jsonStr = jsonEncode(importedChat.toJson());
                          final imported =
                              await utils.ChatJsonUtils.importAllFromJson(
                                jsonStr,
                                onError: (final err) => ob.setImportError(err),
                              );
                          if (imported != null) {
                            await ob.applyChatExport(imported);
                          }
                        },
                      ),
                    ),
                  ),
                  (final route) => false,
                );
              } else if (mounted) {
                setState(() {});
              }
            },
        onClearAllDebug: resetApp,
        onImportJson: (final importedChat) async {
          final jsonStr = jsonEncode(importedChat.toJson());
          final imported = await utils.ChatJsonUtils.importAllFromJson(
            jsonStr,
            onError: (final err) => onboardingLifecycle.setImportError(err),
          );
          if (imported != null) {
            await onboardingLifecycle.applyChatExport(imported);
            if (mounted) setState(() {});
          }
        },
        onboardingLifecycle: onboardingLifecycle,
      );
    }

    // Ensure we only create the ChatController once and pass it down explicitly
    if (_chatController == null) {
      utils.Log.i(
        'MAIN: Creando nuevo ChatController (nueva arquitectura DDD)',
      ); // ✅ DDD: ETAPA 3
      _chatController = di.getChatController(); // ✅ DDD: ETAPA 3

      // Solo persistir datos si realmente hay una biografía válida Y los datos están guardados
      // Esto evita que se persistan datos fantasma después de un resetApp()
      if (onboardingLifecycle.generatedBiography != null &&
          onboardingLifecycle.biographySaved) {
        utils.Log.i(
          'MAIN: Persistiendo biografía: ${onboardingLifecycle.generatedBiography!.aiName}',
        );
        // Schedule persistence and initialization asynchronously. We don't block
        // build(), but ensure the controller is initialized as soon as possible.
        Future(() async {
          try {
            await profile_persist_utils.setOnboardingDataAndPersist(
              onboardingLifecycle.generatedBiography!,
            );
            await _chatController!.initialize();
          } on Exception catch (e) {
            utils.Log.w('MAIN: Async persist+init failed: $e');
          }
          if (mounted) setState(() {});
        });
      } else {
        utils.Log.i(
          'MAIN: NO persistiendo biografía (generatedBiography=${onboardingLifecycle.generatedBiography?.aiName}, biographySaved=${onboardingLifecycle.biographySaved})',
        );
      }

      utils.Log.i(
        'MAIN: ChatController inicializado (carga automática)',
      ); // ✅ DDD: ETAPA 3 - Ya no necesita loadAll() manual
      // _chatController!.loadAll(); // ✅ DDD: ChatController hace carga automática
    } else {
      utils.Log.i(
        'MAIN: Reutilizando ChatController existente',
      ); // ✅ DDD: ETAPA 3
    }

    return ChangeNotifierProvider.value(
      value:
          _chatController, // ✅ DDD: ETAPA 3 COMPLETADA - Usar ChatController directamente
      child: ChatScreen(
        bio: onboardingLifecycle.generatedBiography!,
        aiName: onboardingLifecycle.generatedBiography!.aiName,
        chatController: _chatController!,
        onClearAllDebug: resetApp,
        onImportJson: (final importedChat) async {
          final ob = onboardingLifecycle;
          final jsonStr = jsonEncode(importedChat.toJson());
          final imported = await utils.ChatJsonUtils.importAllFromJson(
            jsonStr,
            onError: (final err) => ob.setImportError(err),
          );
          if (imported != null) {
            await ob.applyChatExport(imported);
          }
        },
      ),
    );
  }
}
