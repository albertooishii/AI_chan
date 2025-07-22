import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/screens/initializing_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/chat_screen.dart';
import 'screens/onboarding_screen.dart';
import 'dart:convert';
import 'providers/onboarding_provider.dart';
import 'providers/chat_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Clave global para navegación
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Función global para borrar toda la cache y datos locales
Future<void> clearAppData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

Future<void> main() async {
  await dotenv.load();
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
        title: 'ＡＩチャン',
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
        home: const MyApp(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
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
    debugPrint('[AI-chan] resetApp llamado');
    await clearAppData();
    debugPrint('[AI-chan] resetApp completado');
    if (mounted) {
      final onboardingProvider = Provider.of<OnboardingProvider>(
        context,
        listen: false,
      );
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
              Map<String, dynamic>? appearance,
            }) async {
              onboardingProvider.setUserName(userName);
              onboardingProvider.setAiName(aiName);
              // meetStory solo se usa aquí y se pasa a la generación de biografía
              await Navigator.of(context).push<AiChanProfile>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => InitializingScreen(
                    bioFuture: () async {
                      await onboardingProvider.generateAndSaveBiography(
                        context: context,
                        userName: userName,
                        aiName: aiName,
                        userBirthday: userBirthday,
                        meetStory: meetStory,
                        appearance: appearance,
                      );
                      if (onboardingProvider.generatedBiography == null) {
                        throw Exception('No se pudo generar la biografía');
                      }
                      return onboardingProvider.generatedBiography!;
                    }(),
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
        final provider = ChatProvider();
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
            final onboardingProvider = Provider.of<OnboardingProvider>(
              context,
              listen: false,
            );
            final jsonStr = jsonEncode(importedChat.toJson());
            await onboardingProvider.importAllFromJson(jsonStr);
          },
        ),
      ),
    );
  }
}
