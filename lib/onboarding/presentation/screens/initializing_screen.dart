import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants.dart';
import 'package:ai_chan/core/models.dart';

class InitializingScreen extends StatefulWidget {
  final Future<AiChanProfile> Function() bioFutureFactory;
  const InitializingScreen({super.key, required this.bioFutureFactory});

  @override
  State<InitializingScreen> createState() => _InitializingScreenState();
}

class _InitializingScreenState extends State<InitializingScreen> {
  final List<List<String>> steps = [
    ["Iniciando sistema", "システム"],
    ["Generando datos básicos", "ベーシック"],
    ["Configurando país de origen", "コクセッテイ"],
    ["Ajustando idioma y acento", "ゲンゴ・アクセント"],
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

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    bool stepsDone = false;
    try {
      final bioFuture = _runGenerationOnce().then((bio) {
        _generatedBio = bio;
        bioReady = true;
        if (stepsDone && mounted && _generatedBio != null) {
          Navigator.of(context, rootNavigator: true).pop(_generatedBio);
        } else if (stepsDone && mounted) {
          setState(() {});
        }
      });
      final stepsFuture = _runSteps().then((_) {
        stepsDone = true;
        if (bioReady && _generatedBio != null && mounted) {
          Navigator.of(context, rootNavigator: true).pop(_generatedBio);
        } else if (mounted) {
          setState(() {});
        }
      });
      await Future.wait([bioFuture, stepsFuture]);
    } catch (e) {
      // En error: ofrecer reintentar o volver
      await _handleErrorWithOptions(e);
    }
  }

  Future<AiChanProfile> _runGenerationOnce() async {
    // Llama a la fábrica y deja que propague errores (incluidos de red)
    return await widget.bioFutureFactory();
  }

  Future<void> _handleErrorWithOptions(Object e) async {
    if (!mounted) return;
    _cancel = true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'No se pudo completar la configuración',
          style: TextStyle(color: AppColors.secondary),
        ),
        content: SingleChildScrollView(
          child: Text(
            e.toString(),
            style: const TextStyle(color: AppColors.primary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text(
              'Volver',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            child: const Text(
              'Reintentar',
              style: TextStyle(color: AppColors.secondary),
            ),
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
      });
      try {
        await Future.wait([
          _runGenerationOnce().then((bio) {
            _generatedBio = bio;
            bioReady = true;
          }),
          _runSteps(),
        ]);
        if (mounted && _generatedBio != null) {
          Navigator.of(context, rootNavigator: true).pop(_generatedBio);
        }
      } catch (err) {
        // Si vuelve a fallar, ofrecer de nuevo
        await _handleErrorWithOptions(err);
      }
    } else {
      // Volver al onboarding
      Navigator.of(context).pop();
    }
  }

  Future<void> _runSteps() async {
    for (var i = 0; i < steps.length; i++) {
      if (!mounted || _cancel) return;
      await Future.delayed(const Duration(milliseconds: 8000));
      if (!mounted || _cancel) return;
      setState(() {
        currentStep = i;
      });
    }
    if (!mounted || _cancel) return;
    setState(() {
      finished = true;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || _cancel) return;
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
                color: AppColors.primary,
                fontSize: 22,
                fontFamily: 'FiraMono',
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
                fontFamily: 'FiraMono',
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}
