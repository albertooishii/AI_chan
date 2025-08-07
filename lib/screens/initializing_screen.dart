import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/dialog_utils.dart';
import '../models/ai_chan_profile.dart';

class InitializingScreen extends StatefulWidget {
  final Future<AiChanProfile> bioFuture;
  const InitializingScreen({super.key, required this.bioFuture});

  @override
  State<InitializingScreen> createState() => _InitializingScreenState();
}

class _InitializingScreenState extends State<InitializingScreen> {
  final List<List<String>> steps = [
    ["Iniciando sistema", "システム"],
    ["Generando datos básicos", "ベーシック"],
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

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    AiChanProfile? generatedBio;
    bool stepsDone = false;
    try {
      final bioFuture = widget.bioFuture.then((bio) {
        generatedBio = bio;
        bioReady = true;
        if (stepsDone && mounted && generatedBio != null) {
          Navigator.of(context, rootNavigator: true).pop(generatedBio);
        } else if (stepsDone && mounted) {
          setState(() {});
        }
      });
      final stepsFuture = _runSteps().then((_) {
        stepsDone = true;
        if (bioReady && generatedBio != null && mounted) {
          Navigator.of(context, rootNavigator: true).pop(generatedBio);
        } else if (mounted) {
          setState(() {});
        }
      });
      await Future.wait([bioFuture, stepsFuture]);
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) async {
    if (!mounted) return;
    await showErrorDialog(context, e.toString());
  }

  Future<void> _runSteps() async {
    for (var i = 0; i < steps.length; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 8000));
      if (!mounted) return;
      setState(() {
        currentStep = i;
      });
    }
    if (!mounted) return;
    setState(() {
      finished = true;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
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
