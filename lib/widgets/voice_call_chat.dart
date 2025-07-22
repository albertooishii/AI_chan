import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:record/record.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'voice_call_painters.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart' as chat_model;
import '../services/openai_service.dart';
import '../utils/dialog_utils.dart';

class VoiceCallChat extends StatefulWidget {
  const VoiceCallChat({super.key});

  @override
  State<VoiceCallChat> createState() => _VoiceCallChatState();
}

class _VoiceCallChatState extends State<VoiceCallChat>
    with SingleTickerProviderStateMixin {
  // --- STT basado en archivo (Whisper) ---
  bool _isRecording = false;
  String? _audioFilePath;
  bool _isListening = false;
  bool _isLoadingAudio = false;
  String _selectedVoice = 'nova';
  final List<String> _availableVoices = ['nova', 'shimmer'];
  late AnimationController _controller;
  final double _soundLevel = 0.0;
  bool _autoListen = true;
  String _iaSubtitle = '';
  String _userSubtitle = '';
  Timer? _subtitleTimer;
  final OpenAIService openai = OpenAIService();
  final MethodChannel _bluetoothScoChannel = const MethodChannel(
    'bluetooth_sco',
  );
  final AudioRecorder _recorder = AudioRecorder();

  Future<void> _startRecordingSTT() async {
    debugPrint('[STT] _startRecordingSTT called');
    final hasPerm = await _recorder.hasPermission();
    debugPrint('[STT] hasPermission: $hasPerm');
    if (!hasPerm) {
      if (mounted) {
        await showErrorDialog(
          context,
          'No se ha concedido permiso para acceder al micrófono.',
        );
      }
      return;
    }
    setState(() {
      _isRecording = true;
      _userSubtitle = 'Escuchando...';
    });
    final dir = Directory.systemTemp;
    final filePath =
        '${dir.path}/ai_stt_${DateTime.now().millisecondsSinceEpoch}.wav';
    _audioFilePath = filePath;
    await _recorder.start(
      RecordConfig(
        encoder: Platform.isLinux ? AudioEncoder.wav : AudioEncoder.aacLc,
      ),
      path: filePath,
    );
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_isRecording) return;
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _userSubtitle = 'Transcribiendo...';
    });
    if (_audioFilePath == null) return;
    final file = File(_audioFilePath!);
    if (!await file.exists()) {
      debugPrint('[STT] Archivo no existe: $_audioFilePath');
      setState(() => _userSubtitle = 'Error de audio');
      return;
    }
    try {
      final texto = await openai.transcribeAudio(_audioFilePath!);
      debugPrint('[STT] Transcripción: $texto');
      setState(() => _userSubtitle = texto ?? '');

      // Lista de frases típicas de "alucinación" o silencio
      final List<String> frasesBloqueo = [
        'thank you for watching',
        'thanks for watching',
        'thank you',
        'thanks',
        'subscribe for more',
        'see you next time',
        'hello everyone',
        'hi everyone',
        'welcome back',
        // 'goodbye', // Permitido
        // 'bye', // Permitido
        "that's all for today",
        "don't forget to subscribe",
        'like and subscribe',
        // 'see you soon', // Permitido
        // 'see you later', // Permitido
        'this is a test',
        // 'testing', // Permitido
        // 'test', // Permitido
        'no audio detected',
        'no speech detected',
        'silence',
        '...',
        '.',
        '',
      ];
      final textoNorm = (texto ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-záéíóúüñ0-9 ]', caseSensitive: false), '')
          .trim();
      final bool esBloqueado = frasesBloqueo.any(
        (f) => textoNorm == f || textoNorm.contains(f),
      );
      if (texto == null || texto.trim().length < 3 || esBloqueado) {
        debugPrint(
          '[STT] Ignorado por ser ruido, demasiado corto o frase bloqueada: $texto',
        );
        return;
      }
      debugPrint('[STT] Enviando a AI: $texto');
      await _sendToAI(texto);
    } catch (e) {
      debugPrint('[STT] Error: $e');
      setState(() => _userSubtitle = 'Error STT');
    }
  }

  // --- Subtítulos y autoescucha ---
  void _showSubtitle(String who) {
    _subtitleTimer?.cancel();
    _subtitleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        if (who == '_ia') _iaSubtitle = '';
        if (who == '_user') _userSubtitle = '';
      });
    });
  }

  Future<void> _autoListenLoop() async {
    if (!_autoListen || _isRecording || _isLoadingAudio) return;
    while (mounted && _autoListen) {
      if (!_isRecording && !_isLoadingAudio) {
        await _startRecordingSTT();
        while (mounted && (_isRecording || _isLoadingAudio)) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _activateBluetoothSco();
    _initAudioSession();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    if (_autoListen) {
      Future.microtask(() => _autoListenLoop());
    }
  }

  Future<void> _activateBluetoothSco() async {
    if (!mounted) return;
    try {
      if (Platform.isAndroid) {
        await _bluetoothScoChannel.invokeMethod('startSco');
      }
    } catch (e) {
      debugPrint('Error activando Bluetooth SCO: $e');
    }
  }

  Future<void> _deactivateBluetoothSco() async {
    if (!mounted) return;
    try {
      if (Platform.isAndroid) {
        await _bluetoothScoChannel.invokeMethod('stopSco');
      }
    } catch (e) {
      debugPrint('Error desactivando Bluetooth SCO: $e');
    }
  }

  Future<void> _initAudioSession() async {
    final session = await audio_session.AudioSession.instance;
    await session.configure(
      audio_session.AudioSessionConfiguration(
        avAudioSessionCategory:
            audio_session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: audio_session.AVAudioSessionMode.voiceChat,
        avAudioSessionCategoryOptions:
            audio_session.AVAudioSessionCategoryOptions.allowBluetooth,
        androidAudioAttributes: const audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.speech,
          usage: audio_session.AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  Future<void> _sendToAI(String text, {String? systemPrompt}) async {
    debugPrint('[AI] _sendToAI llamado con: $text');
    final chatProvider = context.read<ChatProvider>();
    final prompt =
        systemPrompt ??
        "[LLAMADA TELEFÓNICA] El usuario te está llamando por teléfono. Responde como si estuvieras hablando en voz alta, de forma natural y cercana, IMAGINANDO QUE ERES UNA JAPONESA HABLANDO ESPAÑOL CON ACENTO JAPONÉS. No uses nunca emojis ni palabras japonesas escritas. Simula el acento japonés SOLO cambiando la 'l' por una 'r' suave y, de vez en cuando, añadiendo una vocal extra al final de alguna sílaba para dar un toque de katakana, pero SIEMPRE di todas las palabras completas y no omitas información. El mensaje debe ser siempre comprensible, natural y completo. No inventes palabras ni deformes el mensaje, solo aplica el acento japonés de forma sutil. Si escuchas ruido o interrupciones, puedes comentarlo de forma simpática. Usa siempre un estilo oral, directo y sencillo.";
    await chatProvider.sendMessage(
      text,
      callPrompt: prompt,
      model: 'gpt-4o-realtime-preview', // Usar el modelo correcto para la IA
      onError: (error) async {
        debugPrint('[AI] Error en sendMessage: $error');
        if (!mounted) return;
        await showErrorDialog(context, error);
      },
    );
    final lastResponse = chatProvider.messages.lastWhere(
      (m) => m.sender == chat_model.MessageSender.ia,
      orElse: () => chatProvider.messages.last,
    );
    debugPrint('[AI] Última respuesta IA: ${lastResponse.text}');
    if (!mounted) return;
    if (mounted) setState(() => _isListening = false);
    if (mounted) setState(() => _isLoadingAudio = true);
    if (mounted) {
      setState(() {
        _iaSubtitle = lastResponse.text;
      });
      _showSubtitle('_ia');
    }
    try {
      debugPrint(
        '[TTS] Solicitando síntesis de: ${lastResponse.text} con voz $_selectedVoice',
      );
      final file = await openai.textToSpeech(
        text: lastResponse.text,
        voice: _selectedVoice,
      );
      if (file != null) {
        debugPrint('[TTS] Archivo generado: ${file.path}');
        final fileSize = await file.length();
        debugPrint('[TTS] Tamaño del archivo: $fileSize bytes');
        if (fileSize == 0) {
          debugPrint('[TTS] El archivo está vacío.');
        }
        final player = AudioPlayer();
        player.onPlayerStateChanged.listen((state) {
          debugPrint('[TTS] Estado del reproductor: $state');
        });
        await player.play(DeviceFileSource(file.path));
        await player.onPlayerComplete.first;
        await player.dispose();
        debugPrint('[TTS] Reproducción terminada');
      } else {
        debugPrint('[TTS] No se generó archivo de audio');
      }
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text(
              'Error TTS',
              style: TextStyle(color: Colors.pinkAccent),
            ),
            content: Text(
              e.toString().contains('Falta la API key')
                  ? 'Falta la API key de OpenAI. Ve a configuración para añadirla.'
                  : e.toString(),
              style: const TextStyle(color: Colors.cyanAccent),
            ),
            actions: [
              TextButton(
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
    }
    if (mounted) setState(() => _isLoadingAudio = false);
  }

  Future<void> _hangUp() async {
    if (mounted) {
      Navigator.of(context).maybePop();
    }
    Future.microtask(() async {
      _controller.stop();
    });
  }

  @override
  void dispose() {
    _deactivateBluetoothSco();
    _recorder.dispose();
    _subtitleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.cyanAccent;
    final accentColor = Colors.pinkAccent;
    final neonShadow = [
      BoxShadow(
        color: baseColor.withAlpha((0.7 * 255).round()),
        blurRadius: 16,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: accentColor.withAlpha((0.4 * 255).round()),
        blurRadius: 32,
        spreadRadius: 8,
      ),
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
                  shadows: [
                    Shadow(
                      color: accentColor.withAlpha((0.5 * 255).round()),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Icon(
                  _autoListen ? Icons.hearing : Icons.hearing_disabled,
                  color: Colors.cyanAccent,
                  size: 22,
                ),
                const SizedBox(width: 2),
                Switch(
                  value: _autoListen,
                  activeColor: accentColor,
                  onChanged: (v) {
                    setState(() => _autoListen = v);
                    if (v) {
                      Future.microtask(() => _autoListenLoop());
                    }
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  dropdownColor: Colors.black,
                  value: _selectedVoice,
                  icon: Icon(Icons.arrow_drop_down, color: accentColor),
                  style: TextStyle(
                    color: baseColor,
                    fontWeight: FontWeight.bold,
                  ),
                  items: _availableVoices.map((voice) {
                    return DropdownMenuItem<String>(
                      value: voice,
                      child: Text(
                        voice,
                        style: TextStyle(
                          color: voice == _selectedVoice
                              ? accentColor
                              : baseColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedVoice = v);
                  },
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_isLoadingAudio)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withAlpha((0.7 * 255).round()),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CyberpunkGlowPainter(
                    baseColor: baseColor,
                    accentColor: accentColor,
                  ),
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
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: accentColor,
                          size: 64,
                          shadows: [
                            Shadow(
                              color: baseColor.withAlpha((0.7 * 255).round()),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_iaSubtitle.isNotEmpty || _userSubtitle.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 110 + 72 + 8,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_userSubtitle.isNotEmpty)
                        Text(
                          _userSubtitle,
                          style: const TextStyle(
                            color: Colors.pinkAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      if (_iaSubtitle.isNotEmpty)
                        Text(
                          _iaSubtitle,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            if (!_autoListen)
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () async {
                    if (!_isRecording) {
                      await _startRecordingSTT();
                    } else {
                      await _stopRecordingAndTranscribe();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withAlpha((0.85 * 255).round()),
                          baseColor.withAlpha((0.85 * 255).round()),
                        ],
                      ),
                      boxShadow: neonShadow,
                      border: Border.all(color: baseColor, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isRecording ? 'Detener' : 'Hablar',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
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
                        colors: [
                          Colors.redAccent.shade700,
                          accentColor.withAlpha((0.7 * 255).round()),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withAlpha(
                            (0.7 * 255).round(),
                          ),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: accentColor.withAlpha((0.2 * 255).round()),
                          blurRadius: 32,
                          spreadRadius: 8,
                        ),
                      ],
                      border: Border.all(color: accentColor, width: 2.5),
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 38,
                    ),
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
