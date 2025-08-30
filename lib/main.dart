import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import 'package:ai_chan/chat.dart';
import 'dart:convert';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'core/di.dart' as di;
import 'core/di_bootstrap.dart' as di_bootstrap;
import 'package:ai_chan/chat/application/utils/profile_persist_utils.dart'
    as profile_persist_utils;
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_chan/shared/services/firebase_init.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.initialize();
  // Initialize Firebase early so adapters using FirebaseAuth can work.
  // Use the helper that tries native init first and falls back to parsing
  // google-services.json when necessary. Retry a few times to surface
  // intermittent initialization race conditions.
  bool firebaseReady = false;
  const int maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      debugPrint('firebase_init: initialize attempt $attempt/$maxAttempts');
      final ok = await ensureFirebaseInitialized();
      debugPrint('firebase_init: ensureFirebaseInitialized -> $ok');
      if (ok) {
        firebaseReady = true;
        break;
      }
    } catch (e, st) {
      debugPrint('firebase_init: exception on attempt $attempt: $e');
      debugPrint('$st');
    }
    // small backoff
    await Future.delayed(Duration(milliseconds: 200 * attempt));
  }
  if (!firebaseReady) {
    debugPrint(
      'firebase_init: WARNING - failed to initialize Firebase after $maxAttempts attempts. FirebaseAuth calls may throw CONFIGURATION_NOT_FOUND.',
    );
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pinkAccent,
            brightness: Brightness.dark,
          ),
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
    Log.i('resetApp llamado', tag: 'APP');
    await AppDataUtils.clearAllAppData();
    Log.i('resetApp completado', tag: 'APP');
    if (mounted) {
      widget.onboardingProvider.reset();
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
          await Future.delayed(Duration(milliseconds: 500));
          await Permission.storage.request();
        }
      } catch (e) {
        Log.e(
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
      _chatProvider?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final onboardingProvider = widget.onboardingProvider;
    if (onboardingProvider.loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!onboardingProvider.biographySaved) {
      return OnboardingScreen(
        onFinish:
            ({
              required String userName,
              required String aiName,
              required DateTime userBirthday,
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
                    bioFutureFactory:
                        ([void Function(String)? onProgress]) async {
                          await onboardingProvider.generateAndSaveBiography(
                            context: context,
                            userName: userName,
                            aiName: aiName,
                            userBirthday: userBirthday,
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
          final imported =
              await chat_json_utils.ChatJsonUtils.importAllFromJson(
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
      final repo = di.getChatRepository();
      _chatProvider = ChatProvider(repository: repo);
      profile_persist_utils.setOnboardingDataAndPersist(
        _chatProvider!,
        onboardingProvider.generatedBiography!,
      );
      _chatProvider!.loadAll();
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
          final imported =
              await chat_json_utils.ChatJsonUtils.importAllFromJson(
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
