import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'openai_service.dart';
import 'openai_realtime_client.dart';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'tone_service.dart';

/// Controlador para llamadas de voz automáticas con OpenAI Realtime API
class VoiceCallController {
  final OpenAIService openAIService;
  OpenAIRealtimeClient? _client;
  StreamSubscription<Uint8List>? _micSub;
  AudioRecorder? _recorderRef;
  bool _continuous = false;
  bool _muted = false;
  bool _restarting = false; // nuevo: control de reinicio suave
  final _player = AudioPlayer();
  final _ringPlayer = AudioPlayer();
  final List<int> _outAudioBuffer = [];
  bool _isPlayingBack = false; // gate: evita que el micro alimente el audio de la IA
  bool _isRinging = false; // gate: evita eco mientras suena el ringback
  bool _bargeInEnabled = true; // reactivado: permitir interrumpir a la IA
  // Ventana de gracia: durante los primeros ms de reproducción de la IA no permitir barge-in
  int _bargeInGraceMs = 1500;
  // Flag: el usuario habló (voz real detectada) en esta sesión de llamada
  bool _userSpokeDuringSession = false;
  DateTime? _playbackBeganAt;
  double _noiseFloorRms = 1200.0; // estimación adaptativa de ruido ambiente
  static const double _zcrSpeechThreshold = 0.04; // umbral simple para habla (cambios de signo)
  // Detección robusta: acumular ms de voz y comparar ataque vs RMS previo
  double _prevRms = 0.0;
  double _speechMsAccum = 0.0;
  // Nuevo: configuración para reinicios (cambio de voz)
  String? _lastSystemPrompt;
  String? _lastModel;
  String _lastInputAudioFormat = 'pcm16';
  String _lastOutputAudioFormat = 'pcm16';
  final int _lastOutputSampleRate = 24000; // Realtime suele emitir PCM16 a 24 kHz
  String _lastTurnDetectionType = 'server_vad';
  int _lastSilenceDurationMs = 1200;
  void Function(String)? _onTextSaved;
  // Emisor de nivel de micrófono para la UI (0..1)
  final StreamController<double> _micLevelController = StreamController<double>.broadcast();
  Stream<double> get micLevelStream => _micLevelController.stream;
  // Exponer si el usuario habló durante la sesión
  bool get userSpoke => _userSpokeDuringSession;

  // Cadencia y retardo de ringback antes de contestar
  // Nueva lógica: usamos un segmento en loop de 2.5s a 130 BPM, por lo que dejamos 0ms de silencio
  final int _ringbackToneMs = 2500; // longitud del segmento
  final int _minRingbackCyclesBeforeAnswer = 2; // espera más corta (~2 ciclos ≈5s)

  // Tono de colgado accesible desde la UI
  Future<void> playHangupTone({int durationMs = 350}) async {
    try {
      // Delegar reproducción al servicio compartido
      await ToneService.instance.playHangupOrErrorTone(sampleRate: _lastOutputSampleRate, durationMs: durationMs);
    } catch (_) {}
  }

  // Patrones típicos de rechazo/política en EN para colgar la llamada
  final List<RegExp> _refusalPatterns = [
    // Inglés
    RegExp(
      r"\b(i['’` ]?m|i am) (sorry|afraid),? i (can(?:not|\'t)|cannot|can\'t) (assist|help|comply|do) with that\b",
      caseSensitive: false,
    ),
    // Variante con "but" y objetos/verbos flexibles: "I'm sorry, but I can't assist with that."
    RegExp(
      r"\b(i['’` ]?m|i am)\s+(sorry|afraid),?\s*(but\s+)?i\s+(?:can(?:not|\'t)|cannot|can\'t)\s+(?:assist|help|comply|do|provide)(?:\s+with\s+(?:that|this|it)(?:\s+request)?)?\b",
      caseSensitive: false,
    ),
    // Negativa directa sin prefacio de disculpa
    RegExp(
      r"\b(i\s+(?:can(?:not|\'t)|cannot|can\'t)\s+(?:assist|help|comply|provide|do)(?:\s+with\s+(?:that|this|it)(?:\s+request)?)?)\b",
      caseSensitive: false,
    ),
    RegExp(r"\b(i (can(?:not|\'t)|cannot|can\'t) (assist|help|comply|fulfill).{0,30}request)\b", caseSensitive: false),
    RegExp(r"\b(i (must|have to) refuse)\b", caseSensitive: false),
    RegExp(r"\b(this request (violates|is against) (our|the) policies)\b", caseSensitive: false),
    RegExp(r"\b(as an? ai( language)? model)\b", caseSensitive: false),
    RegExp(r"\b(i (cannot|can\'t) provide that)\b", caseSensitive: false),
    RegExp(
      r"\b(i['’` ]?m|i am)\s+unable to\s+(assist|help|comply|provide|answer)(\s+with\s+that(\s+request)?)?\b",
      caseSensitive: false,
    ),
    RegExp(r"\bunable to assist(\s+with\s+that(\s+request)?)?\b", caseSensitive: false),
    RegExp(
      r"\b(i['’` ]?m|i am)\s+not able to\s+(assist|help|comply|provide|answer)(\s+with\s+that(\s+request)?)?\b",
      caseSensitive: false,
    ),
    RegExp(r"\b(i (will not|won't) be able to)\b", caseSensitive: false),
    // Mensajes genéricos de ayuda: "I'm here to help ... provide information. Feel free to ask!"
    RegExp(r"\b(i['’` ]?m|i am)\s+here to help\b.{0,140}\b(provide|privide)\s+information\b", caseSensitive: false),
    RegExp(r"\b(i['’` ]?m|i am)\s+here to help\b.{0,140}\b(feel\s+free\s+to\s+ask)\b", caseSensitive: false),
    RegExp(
      r"\b(i['’` ]?m|i am)\s+here to help\s+with\s+any\s+questions\s+you\s+have(\s+or\s+(?:provide|privide)\s+information)?\b",
      caseSensitive: false,
    ),
  ];

  bool _shouldHangUpForText(String txt) {
    if (txt.isEmpty) return false;
    for (final re in _refusalPatterns) {
      if (re.hasMatch(txt)) return true;
    }
    return false;
  }

  VoiceCallController({required this.openAIService});

  // Normaliza alias de modelos a variantes preview conocidas
  String _normalizeRealtimeModel(String model) {
    var m = model;
    if (m == 'gpt-4o-realtime') m = 'gpt-4o-realtime-preview';
    if (m == 'gpt-4o-mini-realtime') m = 'gpt-4o-mini-realtime-preview';
    if (m == 'gpt-4o-realtime-preview') m = 'gpt-4o-realtime-preview-2025-06-03';
    if (m == 'gpt-4o-mini-realtime-preview') m = 'gpt-4o-mini-realtime-preview-2024-12-17';
    return m;
  }

  /// Inicia la llamada de voz en tiempo real grabando siempre desde el micrófono
  Future<void> startCall({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required void Function(String textChunk) onText,
    void Function(String reasoning)? onReasoning,
    void Function(String summary)? onSummary,
    void Function()? onDone,
    void Function(String reason)? onHangupReason,
    String? model,
    String audioFormat = 'pcm16',
    required Future<Uint8List> Function() grabarAudioMicrofono,
  }) async {
    try {
      // Resetear flag de voz al inicio
      _userSpokeDuringSession = false;
      String chosenModel = _normalizeRealtimeModel(model ?? 'gpt-4o-mini-realtime');
      // Voz desde SharedPreferences o .env con validación y fallback
      final allowedVoices = const {'alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'};
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_voice');
      // Por defecto, usar una voz femenina y cálida (shimmer) si no hay preferencia guardada
      String voicePreset = (saved ?? dotenv.env['OPENAI_VOICE'] ?? 'shimmer').toLowerCase();
      if (!allowedVoices.contains(voicePreset)) voicePreset = 'verse';
      // Normaliza nombres no válidos comunes a sus variantes preview disponibles
      // Normalizado arriba
      // Cliente WebSocket persistente
      _client = OpenAIRealtimeClient(
        model: chosenModel,
        onText: (txt) {
          if (_shouldHangUpForText(txt)) {
            debugPrint('Policy/refusal detectada en texto IA. Colgando llamada.');
            try {
              onHangupReason?.call(
                'La llamada se colgó automáticamente porque el modelo detectó un contenido no permitido o una negativa de respuesta. Prueba a reformular en términos seguros.',
              );
            } catch (_) {}
            stop();
            return;
          }
          // Si detectamos frase de rechazo/política, colgar la llamada
          onText(txt);
        },
        onAudio: (bytes) {
          // TODO: reproducir audio IA (audioplayers)
        },
        onCompleted: () => onDone?.call(),
        onError: (e) {
          debugPrint('Realtime error: $e');
          // Reproducir el tono compartido también para errores de conexión
          try {
            unawaited(ToneService.instance.playHangupOrErrorTone(sampleRate: _lastOutputSampleRate));
          } catch (_) {}
        },
      );
      debugPrint('Realtime: usando modelo $chosenModel');
      await _client!.connect(
        systemPrompt: systemPrompt,
        inputAudioFormat: audioFormat,
        outputAudioFormat: audioFormat,
        voice: voicePreset,
      );
      // Enviar una primera tanda de audio + solicitar respuesta
      final audioBytes = await grabarAudioMicrofono();
      if (audioBytes.isNotEmpty) {
        _client!.appendAudio(audioBytes);
        // Removed manual commit and request response
      } else {
        debugPrint('startCall: no se capturó audio, evitando commit');
      }
    } catch (e) {
      debugPrint('Error en llamada de voz: $e');
      if (onDone != null) onDone();
    }
  }

  Future<void> pushToTalk(Future<Uint8List> Function() grabarAudioMicrofono) async {
    if (_client == null || !_client!.isConnected) return;
    try {
      final audioBytes = await grabarAudioMicrofono();
      if (audioBytes.isNotEmpty) {
        _client!.appendAudio(audioBytes);
        if (audioBytes.length >= 3200) {
          _client!.commitInput();
          _client!.requestResponse(audio: true, text: true);
        } else {
          debugPrint('pushToTalk: audio insuficiente, evitando commit vacío');
        }
      }
    } catch (e) {
      debugPrint('Error push-to-talk: $e');
    }
  }

  Future<void> stop({bool keepFxPlaying = false}) async {
    try {
      _continuous = false;
      // Detener ringback si sigue activo
      await _stopRingback();
      await _micSub?.cancel();
      _micSub = null;
      _outAudioBuffer.clear();
      await _player.stop();
      try {
        await _recorderRef?.stop();
      } catch (_) {}
      await _client?.close();
      // Notificar nivel cero al parar
      try {
        _micLevelController.add(0.0);
      } catch (_) {}
    } catch (_) {}
  }

  void setMuted(bool muted) {
    _muted = muted;
  }

  // Activa/desactiva barge-in (interrumpir a la IA si el usuario empieza a hablar)
  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
  }

  // Configura la ventana de gracia del barge-in (p.ej., 1.0–2.0 s)
  void setBargeInGrace(Duration d) {
    _bargeInGraceMs = d.inMilliseconds.clamp(0, 10000);
  }

  // Getters para estado de UI
  bool get isPlayingBack => _isPlayingBack;
  bool get isRinging => _isRinging;
  bool get isMuted => _muted;
  bool get isInBargeInGrace {
    final began = _playbackBeganAt;
    if (began == null) return false;
    return DateTime.now().difference(began).inMilliseconds < _bargeInGraceMs;
  }

  // Reproduce tono de llamada (ringback) durante un tiempo y se detiene.
  // Útil para simular "no contesta" antes de colgar sin iniciar sesión.
  Future<void> playNoAnswerTone({Duration duration = const Duration(seconds: 8)}) async {
    try {
      await _stopRingback(); // por si acaso
      await _player.stop();
    } catch (_) {}
    await _startRingback();
    try {
      await Future.delayed(duration);
    } catch (_) {}
    await _stopRingback();
  }

  // Cambia la voz en caliente: reinicia la sesión manteniendo la configuración y callbacks
  void setVoice(String voice) {
    final allowed = const {'alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'};
    final v = voice.toLowerCase();
    if (!allowed.contains(v)) return;
    // Persistir preferencia y reiniciar sesión con la nueva voz
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_voice', v);
      } catch (_) {}
      _restartSessionWithVoice(v);
    }();
  }

  Future<void> startContinuousCall({
    required String systemPrompt,
    required void Function(String textChunk) onText,
    required AudioRecorder recorder,
    void Function(String reason)? onHangupReason,
    String? model,
  }) async {
    try {
      _continuous = true;
      _recorderRef = recorder;
      _onTextSaved = onText; // cache handler
      _lastSystemPrompt = systemPrompt;
      // Resetear flag de voz al inicio de la sesión
      _userSpokeDuringSession = false;
      // Iniciar tono de ringback mientras se establece la sesión
      await _startRingback();
      String chosenModel = _normalizeRealtimeModel(model ?? 'gpt-4o-mini-realtime');
      // Voz desde SharedPreferences o .env con validación y fallback
      final allowedVoices = const {'alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'};
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_voice');
      // Por defecto, usar una voz femenina y cálida (shimmer) si no hay preferencia guardada
      String voicePreset = (saved ?? dotenv.env['OPENAI_VOICE'] ?? 'shimmer').toLowerCase();
      if (!allowedVoices.contains(voicePreset)) voicePreset = 'verse';
      _lastModel = chosenModel; // cache modelo normalizado
      _client = OpenAIRealtimeClient(
        model: chosenModel,
        onText: (txt) {
          if (_isRinging) {
            _stopRingback();
          }
          // Si detectamos frase de rechazo/política, colgar la llamada y notificar motivo
          if (_shouldHangUpForText(txt)) {
            debugPrint('Policy/refusal detectada en texto IA. Colgando llamada.');
            try {
              onHangupReason?.call(
                'La llamada se colgó automáticamente porque el modelo detectó un contenido no permitido o una negativa de respuesta. Prueba a reformular en términos seguros.',
              );
            } catch (_) {}
            stop();
            return;
          }
          onText(txt);
        },
        onAudio: (bytes) {
          // Acumular chunks de audio de IA y reproducir tras pequeños cortes
          debugPrint('IA audio chunk: ${bytes.length} bytes');
          if (_isRinging) {
            _stopRingback();
          }
          _outAudioBuffer.addAll(bytes);
        },
        onCompleted: () async {
          debugPrint('IA onCompleted, total buffered: ${_outAudioBuffer.length} bytes');
          if (_outAudioBuffer.isNotEmpty) {
            try {
              // Convertir PCM16 (mono) a WAV con la tasa correcta (Realtime -> 24 kHz)
              final wavBytes = _pcm16ToWav(
                Uint8List.fromList(_outAudioBuffer),
                sampleRate: _lastOutputSampleRate,
                channels: 1,
              );
              // Asegurar que no hay reproducción previa en curso
              try {
                await _player.stop();
              } catch (_) {}
              _isPlayingBack = true;
              _playbackBeganAt = DateTime.now();
              try {
                await _player.play(BytesSource(wavBytes));
                // Esperar a completar para volver a abrir el micro
                await _player.onPlayerComplete.first;
              } finally {
                _isPlayingBack = false;
                _playbackBeganAt = null;
              }
            } catch (e) {
              debugPrint('Audio playback error: $e');
            }
            _outAudioBuffer.clear();
          }
        },
        onError: (e) {
          debugPrint('Realtime error: $e');
          try {
            _stopRingback();
          } catch (_) {}
          // Reproducir el tono compartido también para errores de conexión
          try {
            unawaited(ToneService.instance.playHangupOrErrorTone(sampleRate: _lastOutputSampleRate));
          } catch (_) {}
        },
      );
      // Usar PCM16 para input y output y VAD del servidor
      debugPrint('Realtime: usando modelo $chosenModel');
      _lastInputAudioFormat = 'pcm16';
      _lastOutputAudioFormat = 'pcm16';
      _lastTurnDetectionType = 'server_vad';
      _lastSilenceDurationMs = 1200;
      await _client!.connect(
        systemPrompt: systemPrompt,
        inputAudioFormat: _lastInputAudioFormat,
        outputAudioFormat: _lastOutputAudioFormat,
        voice: voicePreset,
        turnDetectionType: _lastTurnDetectionType,
        silenceDurationMs: _lastSilenceDurationMs,
      );

      // Pedir saludo tras ~2 segmentos de 2.5s (≈5.0s) desde el inicio del ringback
      final cycles = _minRingbackCyclesBeforeAnswer.clamp(1, 6);
      final totalMs = (_ringbackToneMs * cycles) + 20; // pequeño margen
      Future.delayed(Duration(milliseconds: totalMs.clamp(0, 60000)), () async {
        _client?.requestResponse(audio: true, text: true);
      });

      // Iniciar stream de micro en PCM16
      final hasPerm = await recorder.hasPermission();
      if (!hasPerm) throw Exception('Sin permisos de micrófono');
      final stream = await recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _micSub = stream.listen((chunk) {
        if (!_continuous) return;
        if (_restarting) return; // evitar enviar durante reinicio

        // Calcular RMS/ZCR del chunk para UI/barge-in
        double rms = 0.0;
        double zcr = 0.0;
        int samples = 0;
        if (chunk.isNotEmpty) {
          double sum = 0.0;
          int signChanges = 0;
          int prevSign = 0;
          for (int i = 0; i < chunk.lengthInBytes; i += 2) {
            if (i + 1 >= chunk.lengthInBytes) break;
            int s = (chunk[i] | (chunk[i + 1] << 8));
            if (s & 0x8000 != 0) s = s - 0x10000;
            sum += (s * s).toDouble();
            final sg = s > 0 ? 1 : (s < 0 ? -1 : 0);
            if (prevSign != 0 && sg != 0 && sg != prevSign) signChanges++;
            if (sg != 0) prevSign = sg;
          }
          samples = (chunk.lengthInBytes / 2).floor().clamp(1, 1 << 30);
          rms = math.sqrt(sum / samples);
          zcr = (samples > 1) ? (signChanges / (samples - 1)) : 0.0;
          // Actualizar noise floor adaptativo (más sensible a bajadas)
          if (rms < _noiseFloorRms) {
            _noiseFloorRms = (_noiseFloorRms * 0.9) + (rms * 0.1);
          } else {
            _noiseFloorRms = (_noiseFloorRms * 0.98) + (rms * 0.02);
          }
        }

        // Emitir nivel normalizado para la UI (0..1)
        try {
          final bool blocked = _muted || _isRinging || _isPlayingBack || isInBargeInGrace;
          double norm = blocked ? 0.12 : (rms / 10000.0);
          if (!norm.isFinite) norm = 0.0;
          norm = norm.clamp(0.0, 1.0);
          _micLevelController.add(norm);
        } catch (_) {}

        // Si está muteado, no enviar audio al servidor
        if (_muted) return;

        // Barge-in: si estamos reproduciendo y detectamos voz del usuario (tras ventana de gracia),
        // paramos playback y dejamos pasar el audio
        if (_isPlayingBack) {
          if (!_bargeInEnabled) {
            return; // dejar que la IA termine sin interrupciones
          }
          // Respeta ventana de gracia inicial para evitar cortes al saludo
          final began = _playbackBeganAt;
          if (began != null) {
            final elapsedMs = DateTime.now().difference(began).inMilliseconds;
            if (elapsedMs < _bargeInGraceMs) {
              return; // aún en periodo de gracia: no interrumpir
            }
          }
          // Calcular duración aproximada del chunk en ms (16 kHz mono, 2 bytes por muestra)
          final double ms = ((samples) / 16000.0) * 1000.0;
          // Condición: SNR alto, ZCR de habla, guardarraíl absoluto, ataque brusco y voz sostenida
          final bool snrOk = rms > (_noiseFloorRms * 3.5);
          final bool zcrOk = zcr > (_zcrSpeechThreshold + 0.01); // un poco más estricto
          final bool absOk = rms > 6000; // exige cercanía al micro para evitar eco de altavoz
          final bool attackOk = _prevRms > 0 ? (rms > _prevRms * 1.6) : true;
          if (snrOk && zcrOk && absOk && attackOk) {
            _speechMsAccum += ms;
          } else {
            _speechMsAccum = math.max(0.0, _speechMsAccum - (ms * 0.5)); // decaimiento si no cumple
          }
          _prevRms = (rms * 0.4) + (_prevRms * 0.6); // suavizar histórico

          if (_speechMsAccum >= 320.0) {
            // requiere ~320ms de voz continua
            try {
              _player.stop();
            } catch (_) {}
            _isPlayingBack = false; // permitir paso de voz
            _playbackBeganAt = null;
            _speechMsAccum = 0.0;
            if (kDebugMode) {
              // ignore: avoid_print
              print(
                'Barge-in: voz detectada (rms=${rms.toStringAsFixed(0)}, nf=${_noiseFloorRms.toStringAsFixed(0)}, zcr=${zcr.toStringAsFixed(3)})',
              );
            }
          } else {
            return; // seguimos bloqueando mic mientras suena IA
          }
        }

        if (_isRinging) return; // evitar eco: no enviar mientras suena el ringback
        if (chunk.isEmpty) return;
        // Marcar que el usuario habló si detectamos voz por encima de umbrales básicos
        if (!_userSpokeDuringSession) {
          final bool snrOk2 = rms > (_noiseFloorRms * 2.5);
          final bool absOk2 = rms > 3500; // requiere algo de cercanía real
          final bool zcrOk2 = zcr > (_zcrSpeechThreshold - 0.005);
          if (snrOk2 && (absOk2 || zcrOk2)) {
            _userSpokeDuringSession = true;
          }
        }
        _client?.appendAudio(chunk);
      });
      // Con VAD del servidor activo, no necesitamos VAD local
    } catch (e) {
      debugPrint('Error en llamada continua: $e');
      await _stopRingback();
      await stop();
    }
  }

  Future<void> _restartSessionWithVoice(String newVoice) async {
    if (_lastSystemPrompt == null) return;
    if (_restarting) return;
    _restarting = true;
    try {
      await _client?.close();
    } catch (_) {}
    _outAudioBuffer.clear();
    String chosenModel = _normalizeRealtimeModel(_lastModel ?? 'gpt-4o-mini-realtime');
    final onText = _onTextSaved ?? (String _) {};
    _client = OpenAIRealtimeClient(
      model: chosenModel,
      onText: onText,
      onAudio: (bytes) {
        _outAudioBuffer.addAll(bytes);
      },
      onCompleted: () async {
        if (_outAudioBuffer.isNotEmpty) {
          try {
            final wavBytes = _pcm16ToWav(
              Uint8List.fromList(_outAudioBuffer),
              sampleRate: _lastOutputSampleRate,
              channels: 1,
            );
            try {
              await _player.stop();
            } catch (_) {}
            await _player.play(BytesSource(wavBytes));
          } catch (e) {
            debugPrint('Audio playback error (restart): $e');
          }
          _outAudioBuffer.clear();
        }
      },
      onError: (e) => debugPrint('Realtime error (restart): $e'),
    );
    await _client!.connect(
      systemPrompt: _lastSystemPrompt!,
      inputAudioFormat: _lastInputAudioFormat,
      outputAudioFormat: _lastOutputAudioFormat,
      voice: newVoice,
      turnDetectionType: _lastTurnDetectionType,
      silenceDurationMs: _lastSilenceDurationMs,
    );
    _restarting = false;
  }
}

// Helpers locales
extension _PcmWav on VoiceCallController {
  // Reproduce un tono de colgado breve (beep descendente) y espera a que termine (uso interno)
  // Método eliminado: _playHangupToneInternal

  Future<void> _startRingback() async {
    try {
      if (_isRinging) return;
      _isRinging = true;
      // Usa ringback melódico limpio (motivo corto + silencio) en loop
      final wav = ToneService.buildMelodicRingbackWav(sampleRate: 44100, durationSeconds: _ringbackToneMs / 1000.0);
      try {
        await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      } catch (_) {}
      await _ringPlayer.play(BytesSource(wav));
      // Autodesactivar flag al terminar reproducción
      // En modo loop no recibiremos onPlayerComplete; se limpia cuando se detiene manualmente
    } catch (_) {
      _isRinging = false;
    }
  }

  Future<void> _stopRingback() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
  }

  // Crea un contenedor WAV simple (PCM 16-bit) para reproducción
  Uint8List _pcm16ToWav(Uint8List pcm, {required int sampleRate, int channels = 1}) {
    final byteRate = sampleRate * channels * 2; // 16 bits = 2 bytes
    final blockAlign = channels * 2;
    final dataSize = pcm.lengthInBytes;
    final chunkSize = 36 + dataSize;

    final header = BytesBuilder();
    header.add(ascii.encode('RIFF'));
    header.add(_le32(chunkSize));
    header.add(ascii.encode('WAVE'));
    header.add(ascii.encode('fmt '));
    header.add(_le32(16)); // Subchunk1Size for PCM
    header.add(_le16(1)); // AudioFormat PCM
    header.add(_le16(channels));
    header.add(_le32(sampleRate));
    header.add(_le32(byteRate));
    header.add(_le16(blockAlign));
    header.add(_le16(16)); // BitsPerSample
    header.add(ascii.encode('data'));
    header.add(_le32(dataSize));

    final out = BytesBuilder();
    out.add(header.takeBytes());
    out.add(pcm);
    return out.takeBytes();
  }

  // Eliminado: _generateSweepWav (usamos ToneService para generar el WAV compartido)

  Uint8List _le16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  Uint8List _le32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
}
