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
import 'core/di.dart' as di;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

// Clave global para navegación
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// Clave global para el ScaffoldMessenger (mostrar SnackBars desde cualquier sitio)
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// Función global para borrar toda la cache y datos locales
Future<void> clearAppData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Necesario para registrar plugins antes de usarlos
  await Config.initialize();
  runApp(const RootApp());
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingProvider(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'ＡＩチャン',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pinkAccent, brightness: Brightness.dark),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: const MyApp(),
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
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Permite borrar todo y reiniciar la app desde cualquier sitio

  Future<void> resetApp() async {
    Log.i('resetApp llamado', tag: 'APP');
    await clearAppData();
    Log.i('resetApp completado', tag: 'APP');
    if (mounted) {
      final onboardingProvider = Provider.of<OnboardingProvider>(context, listen: false);
      onboardingProvider.reset();
      setState(() {}); // El build ya muestra onboarding limpio
    }
  }

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      // Solicitar permisos de almacenamiento externo en Android
      // Solo si la plataforma es Android
      try {
        // Usar defaultTargetPlatform en lugar de Theme.of(context) en initState
        if (!kIsWeb && Platform.isAndroid) {
          await Future.delayed(Duration(milliseconds: 500)); // Espera a que el contexto esté listo
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
    super.dispose();
  }

  // Carga la biografía desde SharedPreferences (fuera de la clase)

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // Mostrar pantalla de carga hasta que todo esté listo
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Esperar a que OnboardingProvider termine de cargar
    final onboardingProvider = Provider.of<OnboardingProvider>(context);
    if (onboardingProvider.loading) {
      // Si el provider está cargando, mostrar loading
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Si no hay biografía, muestra onboarding
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
              // Capturar navigator y evitar usar context tras esperas largas
              final navigator = Navigator.of(context);
              onboardingProvider.setUserName(userName);
              onboardingProvider.setAiName(aiName);
              // meetStory solo se usa aquí y se pasa a la generación de biografía
              await navigator.push<AiChanProfile>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => InitializingScreen(
                    bioFutureFactory: () async {
                      await onboardingProvider.generateAndSaveBiography(
                        context: context,
                        userName: userName,
                        aiName: aiName,
                        userBirthday: userBirthday,
                        meetStory: meetStory,
                        userCountryCode: userCountryCode,
                        aiCountryCode: aiCountryCode,
                        appearance: appearance,
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
          await onboardingProvider.importAllFromJson(jsonStr);
          if (mounted) setState(() {});
        },
      );
    }
    // Si hay biografía, muestra chat
    return ChangeNotifierProvider(
      create: (_) {
        final repo = di.getChatRepository();
        final chatAdapter = di.getChatResponseService();
        final provider = ChatProvider(repository: repo, chatResponseService: chatAdapter);
        provider.onboardingData = onboardingProvider.generatedBiography!;
        provider.loadAll();
        return provider;
      },
      child: Builder(
        builder: (context) => ChatScreen(
          bio: onboardingProvider.generatedBiography!,
          aiName: onboardingProvider.generatedBiography!.aiName,
          onClearAllDebug: resetApp,
          onImportJson: (importedChat) async {
            final ob = Provider.of<OnboardingProvider>(context, listen: false);
            final jsonStr = jsonEncode(importedChat.toJson());
            await ob.importAllFromJson(jsonStr);
          },
        ),
      ),
    );
  }
}
