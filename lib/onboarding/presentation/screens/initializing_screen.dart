import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/constants.dart';
import 'package:ai_chan/core/models.dart';

class InitializingScreen extends StatefulWidget {
  /// bioFutureFactory can accept an optional progress callback: (String key) -> void
  final Future<AiChanProfile> Function([void Function(String)? onProgress]) bioFutureFactory;
  const InitializingScreen({super.key, required this.bioFutureFactory});

  @override
  State<InitializingScreen> createState() => _InitializingScreenState();
}

class _InitializingScreenState extends State<InitializingScreen> {
  final List<List<String>> steps = [
    ["Iniciando sistema", "システム"],
    ["Generando datos básicos", "ベーシック"],
    ["Configurando país de origen", "コクセッテイ"],
    ["Ajustando idioma", "ゲンゴ"],
    ["Creando historia de encuentro", "ストーリー"],
    ["Generando recuerdos", "メモリー"],
    ["Analizando personalidad", "パーソナリティ"],
    ["Configurando emociones", "エモーション"],
    ["Ajustando empatía", "エンパシー"],
    ["Configurando intereses", "インタレスト"],
    ["Seleccionando aficiones favoritas", "アクティビティ"],
    ["Preparando historia de vida", "ヒストリー"],
    ["Creando historia de encuentro", "ストーリー"],
    ["Generando apariencia física", "フィジカル"],
    ["Seleccionando estilo de ropa", "スタイル"],
    ["Creando avatar digital", "アバター"],
    ["Últimos retoques", "フィニッシュ"],
    ["Finalizando configuración", "コンフィグ"],
  ];

  int currentStep = 0;
  bool finished = false;
  bool bioReady = false;
  bool _cancel = false; // Cancela la animación de pasos si hay error
  AiChanProfile? _generatedBio;
  // Flujo interactivo: ejecutar los pasos mientras se genera la biografía.
  // Ajustado a 0 para que los primeros 4 pasos (índices 0..3) se muestren durante la generación.
  final int initialStepsCount = 0;
  bool startedGeneration = false;
  bool generationDone = false;
  bool _avatarFailed = false; // indica fallo tras intentos en IAAvatarGenerator
  String? _avatarError;
  // Duraciones configurables para ajustar la percepción de tiempo entre fases
  final Duration _stepDuration = const Duration(milliseconds: 5000);
  final Duration _finalPause = const Duration(seconds: 5);
  // Mapa de keys de progreso a índices de steps para actualizaciones desde el proveedor
  final Map<String, int> _progressKeyToIndex = const {
    'start': 0,
    'generating_basic': 1,
    'config_country': 2,
    'adjust_language': 3,
    'meet_story': 4,
    'memories': 5,
    'personality': 6,
    'emotions': 7,
    'empathy': 8,
    'interests': 9,
    'hobbies': 10,
    'life_story': 11,
    'appearance': 12,
    'style': 13,
    'avatar': 14,
    'finish': 15,
    'finalize': 16,
  };

  @override
  void initState() {
    super.initState();
    // Arrancar automáticamente el avance de los primeros pasos y luego la generación.
    _autoAdvanceInitialSteps();
  }

  /// Avanza automáticamente los primeros pasos iniciales y luego lanza la generación.
  Future<void> _autoAdvanceInitialSteps() async {
    if (startedGeneration || _cancel) return;
    for (var i = 0; i < initialStepsCount; i++) {
      if (!mounted || _cancel) return;
      setState(() {
        currentStep = i;
      });
      // breve pausa entre pasos iniciales
      await Future.delayed(const Duration(milliseconds: 1000));
    }
    if (!mounted || _cancel) return;
    // Tras avanzar los pasos iniciales, iniciar la generación y mostrar los pasos restantes
    await _startGenerationAndRunRemainingSteps();
  }

  /// Inicia la generación (llama a la fábrica) y lanza la animación de pasos restantes.
  Future<void> _startGenerationAndRunRemainingSteps() async {
    if (startedGeneration || _cancel) return;
    startedGeneration = true;
    bool stepsDone = false;
    try {
      final appearanceStartedCompleter = Completer<void>();
      final avatarStartedCompleter = Completer<void>();
      final finalizeCompleter = Completer<void>();

      // Pasar un callback de progreso a la fábrica para recibir updates reales
      final bioFuture =
          _runGenerationOnceWithProgress((key) {
            if (!mounted || _cancel) return;
            final idx = _progressKeyToIndex[key];
            if (idx != null) {
              setState(() {
                currentStep = idx;
              });
            }
            if (key == 'appearance' && !appearanceStartedCompleter.isCompleted) {
              appearanceStartedCompleter.complete();
            }
            if (key == 'avatar' && !avatarStartedCompleter.isCompleted) {
              avatarStartedCompleter.complete();
            }
            if (key == 'finalize' && !finalizeCompleter.isCompleted) {
              finalizeCompleter.complete();
            }
          }).then((bio) {
            _generatedBio = bio;
            bioReady = true;
            generationDone = true;
            if (stepsDone && mounted && _generatedBio != null) {
              Navigator.of(context, rootNavigator: true).pop(_generatedBio);
            } else if (stepsDone && mounted) {
              setState(() {});
            }
          });

      // Phase 1: animate biography steps (0..11) while waiting for 'appearance'
      final bioAnimFuture = () async {
        for (var i = 0; i <= 11; i++) {
          if (!mounted || _cancel) return;
          // If appearance has started, stop bio animation early
          if (appearanceStartedCompleter.isCompleted) break;
          setState(() {
            currentStep = i;
          });
          await Future.delayed(_stepDuration);
        }
      }();

      // Phase 2: once 'appearance' signaled, animate appearance steps (12..13)
      final appearancePhaseFuture = appearanceStartedCompleter.future.then((_) async {
        for (var i = 12; i <= 13; i++) {
          if (!mounted || _cancel) return;
          // If avatar has started, stop appearance animation early
          if (avatarStartedCompleter.isCompleted) break;
          setState(() {
            currentStep = i;
          });
          await Future.delayed(_stepDuration);
        }
      });

      // Phase 3: animate avatar steps (14..15) while waiting for 'finalize'
      final avatarPhaseFuture = avatarStartedCompleter.future.then((_) async {
        for (var i = 14; i <= 15; i++) {
          if (!mounted || _cancel) return;
          // If finalize already occurred, stop
          if (finalizeCompleter.isCompleted) break;
          setState(() {
            currentStep = i;
          });
          await Future.delayed(_stepDuration);
        }
      });

      // When finalize happens, show step 16 for a short moment (UI pause)
      final finalizeFuture = finalizeCompleter.future.then((_) async {
        if (!mounted || _cancel) return;
        setState(() {
          currentStep = 16;
        });
        // Mantener visible unos segundos (coincide con provider) antes de cerrar
        await Future.delayed(_finalPause);
      });

      // Esperar a que la bio generation y las fases de animación completen
      await Future.wait([bioFuture, bioAnimFuture, appearancePhaseFuture, avatarPhaseFuture, finalizeFuture]);
      stepsDone = true;
      if (bioReady && _generatedBio != null && mounted) {
        Navigator.of(context, rootNavigator: true).pop(_generatedBio);
      } else if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Si el error proviene de IAAvatarGenerator por agotar intentos, mostrar opciones en UI
      final msg = e.toString();
      if (msg.contains('No se pudo generar el avatar') || msg.contains('No se pudo generar el avatar tras')) {
        if (!mounted) return;
        setState(() {
          _cancel = true;
          _avatarFailed = true;
          _avatarError = msg;
        });
      } else {
        await _handleErrorWithOptions(e);
      }
    }
  }

  Future<AiChanProfile> _runGenerationOnceWithProgress(void Function(String) onProgress) async {
    return await widget.bioFutureFactory(onProgress);
  }

  Future<void> _handleErrorWithOptions(Object e) async {
    if (!mounted) return;
    _cancel = true;
    final choice = await showAppDialog<String>(
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('No se pudo completar la configuración', style: TextStyle(color: AppColors.secondary)),
        content: SingleChildScrollView(
          child: Text(e.toString(), style: const TextStyle(color: AppColors.primary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Volver', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            child: const Text('Reintentar', style: TextStyle(color: AppColors.secondary)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'retry') {
      // Reiniciar pasos y proceso
      setState(() {
        _cancel = false;
        currentStep = 0;
        finished = false;
        bioReady = false;
        _generatedBio = null;
        startedGeneration = false;
        generationDone = false;
      });
      try {
        // Reiniciar: arrancar automáticamente el avance inicial y la generación.
        setState(() {});
        _autoAdvanceInitialSteps();
      } catch (err) {
        // Si vuelve a fallar, ofrecer de nuevo
        await _handleErrorWithOptions(err);
      }
    } else {
      // Volver al onboarding
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.memory, color: AppColors.secondary, size: 64),
            const SizedBox(height: 32),
            Text(
              steps[currentStep][0],
              style: const TextStyle(
                color: AppColors.cyberpunkYellow,
                fontSize: 22,
                fontFamily: 'monospace',
                letterSpacing: 2,
                shadows: [Shadow(color: AppColors.secondary, blurRadius: 12)],
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              steps[currentStep][1],
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 20,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Si la generación de avatar falló tras intentos, mostrar botones para reintentar o volver
            if (_avatarFailed) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _avatarError ?? 'Error generando avatar',
                  style: const TextStyle(color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Reintentar generación
                      setState(() {
                        _cancel = false;
                        _avatarFailed = false;
                        _avatarError = null;
                        currentStep = 0;
                        finished = false;
                        bioReady = false;
                        _generatedBio = null;
                        startedGeneration = false;
                        generationDone = false;
                      });
                      _autoAdvanceInitialSteps();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                    child: const Text('Reintentar'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Volver'),
                  ),
                ],
              ),
            ] else ...[
              // Spinner normal (cuando no hay fallo de avatar)
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(color: AppColors.secondary, strokeWidth: 4),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
