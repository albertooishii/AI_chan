import 'package:record/record.dart';
import 'dart:io';

import '../services/openai_service.dart';
import '../services/voice_call_controller.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'voice_call_painters.dart';

class VoiceCallChat extends StatefulWidget {
  const VoiceCallChat({super.key});

  @override
  State<VoiceCallChat> createState() => _VoiceCallChatState();
}

class _VoiceCallChatState extends State<VoiceCallChat> with SingleTickerProviderStateMixin {
  Future<void> _hangUp() async {
    if (mounted) {
      Navigator.of(context).maybePop();
    }
    Future.microtask(() async {
      _controller.stop();
    });
  }

  String _iaSubtitle = '';
  Timer? _subtitleTimer;
  final OpenAIService openai = OpenAIService();
  late final VoiceCallController controller;
  final AudioRecorder _recorder = AudioRecorder();

  void _showSubtitle(String text) {
    if (!mounted) return;
    setState(() => _iaSubtitle = text);
    _subtitleTimer?.cancel();
    _subtitleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _iaSubtitle = '';
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    controller = VoiceCallController(openAIService: openai);
    // Ejemplo mínimo de llamada de voz en tiempo real usando el controlador y audio del micrófono
    final promptBasico = "Eres un asistente útil. Responde de forma breve.";
    final historialBasico = [
      {'role': 'user', 'content': 'Hola, ¿qué puedes hacer?'},
    ];
    Future.microtask(() async {
      await controller.startCall(
        systemPrompt: promptBasico,
        history: historialBasico,
        onText: (chunk) => _showSubtitle(chunk),
        onReasoning: (r) => print('Razonamiento: $r'),
        onSummary: (s) => print('Resumen: $s'),
        onDone: () => print('Llamada finalizada'),
        model: 'gpt-4o-realtime-preview',
        audioFormat: Platform.isLinux ? 'wav' : 'aac',
        grabarAudioMicrofono: () async {
          // Graba audio y devuelve los bytes
          final hasPerm = await _recorder.hasPermission();
          if (!hasPerm) throw Exception('Sin permisos de micrófono');
          final dir = Directory.systemTemp;
          final filePath =
              '${dir.path}/ai_stt_${DateTime.now().millisecondsSinceEpoch}.${Platform.isLinux ? 'wav' : 'aac'}';
          await _recorder.start(
            RecordConfig(encoder: Platform.isLinux ? AudioEncoder.wav : AudioEncoder.aacLc),
            path: filePath,
          );
          // Espera a que el usuario hable y se detecte silencio (puedes mejorar la lógica)
          await Future.delayed(const Duration(seconds: 3));
          await _recorder.stop();
          final file = File(filePath);
          if (!await file.exists()) throw Exception('No se grabó audio');
          return await file.readAsBytes();
        },
      );
    });
  }

  late AnimationController _controller;
  final double _soundLevel = 0.0;

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.cyanAccent;
    final accentColor = Colors.pinkAccent;
    final neonShadow = [
      BoxShadow(color: baseColor.withAlpha((0.7 * 255).round()), blurRadius: 16, spreadRadius: 2),
      BoxShadow(color: accentColor.withAlpha((0.4 * 255).round()), blurRadius: 32, spreadRadius: 8),
    ];
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _hangUp();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: Row(
            children: [
              Icon(Icons.phone_in_talk, color: accentColor, size: 28),
              const SizedBox(width: 8),
              Text(
                'AI-Chan',
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 1.2,
                  shadows: [Shadow(color: accentColor.withAlpha((0.5 * 255).round()), blurRadius: 8)],
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            // Eliminado: indicador de carga de audio innecesario
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CyberpunkGlowPainter(baseColor: baseColor, accentColor: accentColor),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 40.0),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: WavePainter(
                              animation: _controller.value,
                              soundLevel: _soundLevel,
                              baseColor: baseColor,
                              accentColor: accentColor,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: neonShadow,
                          border: Border.all(color: accentColor, width: 3),
                          gradient: RadialGradient(
                            colors: [
                              Colors.black,
                              accentColor.withAlpha((0.15 * 255).round()),
                              baseColor.withAlpha((0.10 * 255).round()),
                            ],
                            stops: const [0.7, 0.9, 1.0],
                          ),
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Icon(
                          Icons.mic_none,
                          color: accentColor,
                          size: 64,
                          shadows: [Shadow(color: baseColor.withAlpha((0.7 * 255).round()), blurRadius: 16)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_iaSubtitle.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 110 + 72 + 8,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      _iaSubtitle,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    await _hangUp();
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.redAccent.shade700, accentColor.withAlpha((0.7 * 255).round())],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withAlpha((0.7 * 255).round()),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                        BoxShadow(color: accentColor.withAlpha((0.2 * 255).round()), blurRadius: 32, spreadRadius: 8),
                      ],
                      border: Border.all(color: accentColor, width: 2.5),
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 38),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
