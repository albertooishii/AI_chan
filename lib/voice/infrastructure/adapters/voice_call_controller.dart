import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:record/record.dart';

import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/shared/constants/voices.dart';
import 'google_speech_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'tone_service.dart';
import 'package:ai_chan/core/models.dart';
import 'audio_playback_strategy_factory.dart';
// duplicate import removed
import 'package:ai_chan/shared/utils/log_utils.dart';

class VoiceCallController {
  final IAIService aiService;
  late AudioPlayer _audioPlayer;
  late AudioPlayer _ringPlayer;

  // Buffer de salida acumulado (se reproduce una vez que termina la respuesta)
  final List<int> _continuousAudioBuffer = [];
  // Mapeo 1:1 chunk audio -> chunk subtítulo (modo directo único)
  final List<_AudioChunkMeta> _audioChunkMetas = [];
  int _totalOutputSamples = 0; // muestras PCM16 (mono) acumuladas
  // Conteo total de caracteres asignados (si se necesitara para debug futuro se puede restaurar)
  StringBuffer? _preAudioTextBuffer; // texto recibido antes del primer audio
  // Buffer de texto de la respuesta antes de mostrarlo (subtítulos escalonados)
  final List<String> _pendingAiTextSegments = [];
  // Texto consolidado actual de la respuesta AI
  String _currentAiResponseText = '';
  bool _aiMessagePendingCommit = false; // asegurar 1 mensaje por respuesta AI
  bool _isStreaming = false; // streaming lógico activo
  bool _isPlayingComplete = false; // actualmente reproduciendo audio AI
  bool _audioStartedForCurrentResponse =
      false; // gating para subtítulos: true solo cuando comienza audio real
  bool _shouldMuteMic = false; // micrófono gateado mientras AI habla/genera
  Timer? _playbackTimer;
  Timer? _subtitleRevealTimer;
  int _subtitleRevealIndex = 0; // índice de caracteres ya mostrados
  String _fullAiText = '';
  Function(String)? _uiOnText; // referencia al callback UI original
  bool _suppressFurtherAiText =
      false; // suprimir subtítulos tras end_call detectado
  bool get suppressFurtherAiTextFlag =>
      _suppressFurtherAiText; // exposición de solo lectura para UI
  bool _firstAudioReceived = false;
  bool _ringbackActive = false;
  bool _disposed =
      false; // bandera de ciclo de vida para evitar callbacks tras dispose
  static const int _ringbackMaxMs = 10000; // tope máximo ampliado (10s)
  // Ajuste: ampliar a 10000ms para permitir etiqueta [start_call] antes de audio
  static const int _ringbackMinMs =
      5500; // asegurar 2-3 loops (~2.5s cada) antes de cortar
  // Eliminamos ringback mínimo rígido para evitar solapes con voz AI; se detendrá al primer audio.
  DateTime? _ringbackStartAt;
  DateTime? _playbackStartAt;
  // Ajustado: permitir hablar antes para no recortar primeras sílabas del usuario
  static const double _earlyUnmuteProgress = 0.48; // antes 0.65
  // Debug subtítulos
  final bool _subtitleDebug =
      true; // desactivado: logs de subtítulos silenciados
  int _lastLoggedSubtitleChars = 0;
  // Latencia artificial para que los subtítulos vayan detrás del audio simulando procesamiento.
  int _subtitleLagMs = 1000; // ajustable (reducido en modo directo)
  // Ya no usamos milestones heurísticos; pacing proporcional directo.

  // Estado de conexión
  dynamic _client;
  bool _isConnected = false;
  bool _isMuted = false; // estado actual de mute (usuario)
  String _currentVoice = resolveDefaultVoice(Config.getOpenaiVoice());
  bool _micStarted =
      false; // micrófono aún no iniciado (diferido hasta start_call o audio IA)
  bool _startingMic = false; // previene arranques concurrentes
  DateTime? _lastMicStartAt;
  bool _pendingSecondPhaseAudio =
      false; // reintento diferido de audio si fallback fue saltado
  int _responseFailureCount =
      0; // conteo de fallos de respuesta para reintentos

  // Captura de audio
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;

  // Seguimiento de la llamada (para resumen)
  DateTime? _callStartTime;
  DateTime? get callStartTime => _callStartTime;
  final List<VoiceCallMessage> _callMessages = [];
  bool _userSpoke = false;
  bool _aiResponded = false;
  bool get userSpokeFlag => _userSpoke;
  bool get aiRespondedFlag => _aiResponded;
  bool get firstAudioReceivedFlag =>
      _firstAudioReceived; // nuevo getter para decidir si realmente contestó la IA
  // Auto-gain para mejorar claridad de ASR
  final bool _enableMicAutoGain = true;
  // Parámetros AGC (auto gain control) adaptativo
  // AGC ajustado para reducir amplificación de ruido constante (ventilador) y bombeo
  final double _agcTargetRms = 0.145; // antes 0.18
  final double _agcMaxGain = 3.8; // antes 5.0
  double _agcNoiseFloorRms = 0.0; // estimación de ruido de fondo
  final double _agcNoiseFloorAlpha = 0.05; // suavizado del ruido
  final double _agcAttack = 0.25; // antes 0.35 (menos agresivo)
  final double _agcRelease = 0.10; // antes 0.08 (algo más lento al bajar)
  double _agcCurrentGain = 1.0; // ganancia suavizada actual

  // AGC adaptativo: eleva voz baja sin subir mucho el ruido ni recortar picos
  Uint8List _applyAutoGain(Uint8List bytes) {
    if (!_enableMicAutoGain || bytes.isEmpty) return bytes;
    final len = bytes.length & ~1;
    if (len == 0) return bytes;

    // 1. Calcular RMS bruto + pico y estimar ruido de fondo
    double sumSq = 0.0;
    double peak = 0.0;
    int count = 0;
    for (int i = 0; i < len; i += 2) {
      int s = bytes[i] | (bytes[i + 1] << 8);
      if (s & 0x8000 != 0) s -= 0x10000;
      final f = s / 32768.0;
      sumSq += f * f;
      final a = f.abs();
      if (a > peak) peak = a;
      count++;
    }
    if (count == 0) return bytes;
    double rms = math.sqrt(sumSq / count);

    // 2. Actualizar noise floor cuando estamos claramente en silencio (rms bajo y sin picos)
    if (rms < 0.02 && peak < 0.05) {
      if (_agcNoiseFloorRms == 0.0) {
        _agcNoiseFloorRms = rms;
      } else {
        _agcNoiseFloorRms =
            _agcNoiseFloorRms * (1 - _agcNoiseFloorAlpha) +
            rms * _agcNoiseFloorAlpha;
      }
    }

    // 3. Sustraer ruido estimado (sin quedar negativo)
    double speechRms = rms - _agcNoiseFloorRms;
    if (speechRms < 1e-5) speechRms = 1e-5;

    // 4. Ganancia deseada para alcanzar target
    final desiredGain = (_agcTargetRms / speechRms).clamp(1.0, _agcMaxGain);

    // 5. Suavizado (attack más rápido que release)
    if (desiredGain > _agcCurrentGain) {
      _agcCurrentGain += (desiredGain - _agcCurrentGain) * _agcAttack;
    } else {
      _agcCurrentGain += (desiredGain - _agcCurrentGain) * _agcRelease;
    }

    // 6. No amplificar solo ruido: si rms casi igual a noise floor, bajar ganancia efectiva
    double noiseRatio = (_agcNoiseFloorRms > 0)
        ? (_agcNoiseFloorRms / rms).clamp(0.0, 1.0)
        : 0.0;
    // Si ruido es >60% del total, recortar ganancia proporcionalmente
    double effectiveGain = _agcCurrentGain * (1.0 - (noiseRatio * 0.6));
    if (effectiveGain < 1.0) effectiveGain = 1.0; // mantener al menos unidad

    // 7. Aplicar con soft clipping (curva suave) para evitar distorsión dura
    final out = Uint8List(len);
    for (int i = 0; i < len; i += 2) {
      int s = bytes[i] | (bytes[i + 1] << 8);
      if (s & 0x8000 != 0) s -= 0x10000;
      double x = (s / 32768.0) * effectiveGain;
      // Soft clip: tanh aproximado usando serie racional para no importar dart:math tanh cada muestra
      // tanh(x) ~ x * (27 + x^2) / (27 + 9x^2)
      final x2 = x * x;
      final soft = x * (27.0 + x2) / (27.0 + 9.0 * x2);
      double y = soft;
      if (y > 1.0) y = 1.0;
      if (y < -1.0) y = -1.0;
      int si = (y * 32767.0).toInt();
      out[i] = si & 0xFF;
      out[i + 1] = (si >> 8) & 0xFF;
    }

    // 8. Ocasional debug (no spam): cada ~500ms según timestamp mod
    if (kDebugMode) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs % 500 < 20) {
        debugPrint(
          '🎚️ AGC rms=${rms.toStringAsFixed(3)} nf=${_agcNoiseFloorRms.toStringAsFixed(3)} g=${effectiveGain.toStringAsFixed(2)}',
        );
      }
    }

    return out;
  }

  // Parámetros WAV
  final int _lastOutputSampleRate = 24000;

  // Nivel de micro para UI
  final _micLevelController = StreamController<double>.broadcast();
  Stream<double> get micLevelStream => _micLevelController.stream;

  VoiceCallController({required this.aiService}) {
    _audioPlayer = AudioPlayer();
    _ringPlayer = AudioPlayer();
    // Listener para detectar fin REAL de reproducción de audio (voz AI acabó de hablar)
    _audioPlayer.onPlayerComplete.listen((event) {
      // Evitar doble ejecución si ya limpiamos por timer/fallback
      if (_isPlayingComplete) {
        if (_subtitleDebug) {
          debugPrint('✅ [AUDIO] onPlayerComplete: fin de voz');
        }
        _isPlayingComplete = false;
        _shouldMuteMic = false;
        _isMuted = false; // permitir inmediatamente al usuario
        // Antes forzábamos el final inmediato de subtítulos aquí. Lo eliminamos para
        // permitir que el revelado siga su curso con el lag artificial (_subtitleLagMs)
        // y así mantener la sensación de "procesamiento" incluso tras acabar el audio.
        // Solo forzaríamos en caso extremo (timer nulo y texto no mostrado), lo cual
        // ya lo cubre la lógica de inicio.
        debugPrint(
          '🎤 Mic ungated after playback (fin respuesta - audio real)',
        );
      }
    });
  }

  // ========== MICROPHONE CAPTURE ==========

  Future<void> _startMicrophoneCapture() async {
    debugPrint('🎤 Starting microphone capture (low-level)...');
    _recorder ??= AudioRecorder();
    try {
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        debugPrint('❌ Microphone permission denied');
        return;
      }
      final stream = await _recorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _micSub = stream.listen((audioChunk) {
        final aiTalking = _shouldMuteMic || _isPlayingComplete;
        if (_client != null && _isConnected && !_isMuted && !aiTalking) {
          final processed = _applyAutoGain(audioChunk);
          _client!.appendAudio(processed);
        }
        // Mic level aproximado (media de valores absolutos)
        double level = 0.0;
        if (audioChunk.isNotEmpty) {
          double sum = 0.0;
          int samples = 0;
          for (int i = 0; i < audioChunk.lengthInBytes; i += 2) {
            if (i + 1 >= audioChunk.lengthInBytes) break;
            int s = (audioChunk[i] | (audioChunk[i + 1] << 8));
            if (s & 0x8000 != 0) s = s - 0x10000;
            sum += s.abs();
            samples++;
          }
          if (samples > 0) level = (sum / samples) / 32768.0;
        }
        _micLevelController.add((_isMuted || aiTalking) ? 0.0 : (level * 0.6));
      });
      debugPrint('🎤 Microphone capture started (low-level)');
    } catch (e) {
      debugPrint('❌ Error starting microphone: $e');
    }
  }

  /// Wrapper con debounce/concurrency guard para iniciar el mic una sola vez.
  Future<void> ensureMicStarted() async {
    if (_micStarted) {
      // Ya activo; opcionalmente refresh status
      return;
    }
    if (_startingMic) {
      // Otro flujo lo está iniciando: esperar breve
      for (int i = 0; i < 15; i++) {
        if (_micStarted) return;
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return; // salir aunque no haya arrancado para evitar bloqueo
    }
    final now = DateTime.now();
    if (_lastMicStartAt != null &&
        now.difference(_lastMicStartAt!) < const Duration(milliseconds: 600)) {
      debugPrint('⏱️ Debounce mic start (último inicio hace <600ms)');
      return;
    }
    _startingMic = true;
    try {
      await _startMicrophoneCapture();
      _micStarted = true;
      _lastMicStartAt = DateTime.now();
      debugPrint('✅ Mic ensureMicStarted listo');
    } catch (e) {
      debugPrint('❌ ensureMicStarted fallo: $e');
    } finally {
      _startingMic = false;
    }
  }

  Future<void> _stopMicrophoneCapture() async {
    try {
      await _micSub?.cancel();
      _micSub = null;

      if (_recorder != null) {
        await _recorder!.stop();
      }

      debugPrint('🎤 Microphone capture stopped');
    } catch (e) {
      debugPrint('❌ Error stopping microphone: $e');
    }
  }

  // ========== COMPATIBILITY METHODS FOR UI ==========

  void setMuted(bool muted) {
    _isMuted = muted;
    debugPrint('🎤 Muted: $muted');

    // Additional diagnostic info
    if (muted) {
      debugPrint('⚠️ WARNING: User will not be able to speak while muted');
    } else {
      debugPrint('✅ User can now speak - microphone active');
    }
  }

  // Method to check current microphone status
  void printMicrophoneStatus() {
    debugPrint('🎤 Microphone Status Report:');
    debugPrint('   - User muted: $_isMuted');
    debugPrint('   - Auto-muted (AI talking): $_shouldMuteMic');
    debugPrint('   - Connected: $_isConnected');
    debugPrint('   - Streaming: $_isStreaming');
    debugPrint('   - Playing complete audio: $_isPlayingComplete');
    debugPrint('   - User spoke this call: $_userSpoke');
    final effectivelyMuted = _isMuted || _shouldMuteMic || !_isConnected;
    debugPrint(
      effectivelyMuted
          ? '⚠️ MICROPHONE EFFECTIVELY MUTED'
          : '✅ MICROPHONE ACTIVE',
    );
  }

  Future<void> stop({bool keepFxPlaying = false}) async {
    debugPrint(
      '🛑 Stopping VoiceCallController (keepFxPlaying: $keepFxPlaying)',
    );
    _shouldMuteMic = false;
    await _stopMicrophoneCapture();
    if (keepFxPlaying) {
      // Evitar detener el reproductor principal para que el tono de colgado siga sonando.
      // Solo marcamos flags de streaming como inactivos.
      _isStreaming = false;
      debugPrint('🎵 Manteniendo reproductor activo para FX (hangup tone)');
      // Pero aseguramos que cualquier ringback residual se detenga para no solaparse con el tono de colgado
      if (_ringbackActive) {
        try {
          await _stopRingback();
        } catch (_) {}
        _ringbackActive = false;
        debugPrint('🔔 Ringback detenido durante stop(keepFxPlaying)');
      }
    } else {
      await stopStreaming();
    }
    _playbackTimer?.cancel();
    _playbackTimer = null;
    // Cancelar revelado progresivo si estaba activo para evitar que siga imprimiendo/logueando tras colgar
    if (_subtitleRevealTimer != null) {
      _subtitleRevealTimer!.cancel();
      _subtitleRevealTimer = null;
    }
    if (_client != null) {
      await _client!.close();
      _client = null;
      _isConnected = false;
    }
  }

  Future<void> playHangupTone() async {
    try {
      final hangupToneWav = ToneService.buildHangupOrErrorToneWav(
        sampleRate: _lastOutputSampleRate,
        durationMs: 500,
      );

      final directory = await getTemporaryDirectory();
      final tempFile = File('${directory.path}/hangup_tone.wav');
      await tempFile.writeAsBytes(hangupToneWav);

      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      debugPrint('📞 Playing real hangup tone');
    } catch (e) {
      debugPrint('Error playing hangup tone: $e');
      await Future.delayed(const Duration(milliseconds: 500)); // Fallback
    }
  }

  Future<void> playNoAnswerTone({
    Duration duration = const Duration(seconds: 6),
  }) async {
    try {
      await _startRingback();
      await Future.delayed(duration);
      await _stopRingback();
      debugPrint(
        '📞 Playing melodic no answer tone for ${duration.inSeconds}s',
      );
    } catch (e) {
      debugPrint('Error playing no answer tone: $e');
      await Future.delayed(duration); // Fallback
    }
  }

  // ===== Ring entrante público =====
  Future<void> startIncomingRing() async {
    if (_ringbackActive) return;
    try {
      await _startRingback();
      _ringbackActive = true;
      _ringbackStartAt = DateTime.now();
      debugPrint('📞 Incoming ring started');
    } catch (e) {
      debugPrint('Error starting incoming ring: $e');
    }
  }

  Future<void> stopIncomingRing() async {
    if (!_ringbackActive) return;
    try {
      await _stopRingback();
    } catch (e) {
      debugPrint('Error stopping incoming ring: $e');
    }
    _ringbackActive = false;
    debugPrint('📞 Incoming ring stopped');
  }

  // Método genérico para detener ringback (entrante o saliente) si sigue activo
  Future<void> stopRingback() async {
    if (!_ringbackActive) return;
    try {
      await _stopRingback();
    } catch (e) {
      debugPrint('Error stopping ringback: $e');
    }
    _ringbackActive = false;
    debugPrint('🔕 Ringback tone stopped (generic)');
  }

  Future<void> _startRingback() async {
    try {
      final ringbackWav = ToneService.buildMelodicRingbackWav(
        sampleRate: _lastOutputSampleRate,
      );

      final directory = await getTemporaryDirectory();
      final tempFile = File('${directory.path}/ringback_tone.wav');
      await tempFile.writeAsBytes(ringbackWav);

      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('Error starting ringback: $e');
    }
  }

  Future<void> _stopRingback() async {
    try {
      await _ringPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping ringback: $e');
    }
  }

  Future<void> startContinuousCall({
    required String systemPrompt,
    required Function(String) onText,
    Function(String)? onHangupReason,
    Function(String)?
    onUserTranscription, // Nuevo callback para transcripciones del usuario
    dynamic recorder, // Para compatibilidad
    String? model,
    String? voice,
    bool suppressInitialAiRequest =
        false, // nuevo: IA no habla hasta que user hable
    bool playRingback =
        true, // nuevo: controlar si reproducir ringback (entrante respondida no)
    bool twoPhaseInitial =
        true, // Opción 1: primera generación SOLO texto para permitir [end_call][/end_call]
    Function(int attempt, int backoffMs)?
    onRetryScheduled, // notificar reintentos
  }) async {
    // Determinar voz efectiva: preferencia guardada -> argumento -> .env -> fallback lista
    String effectiveVoice = voice ?? _currentVoice;
    final providerName = _getRealtimeProvider().name;
    List<String> googleVoices = [];
    if (providerName == 'google' && GoogleSpeechService.isConfigured) {
      // Obtener voces femeninas filtradas para español (España)
      try {
        final fetchedVoices = await GoogleSpeechService.voicesForUserAndAi(
          ['es-ES'],
          ['es-ES'],
        );
        googleVoices = fetchedVoices.map((v) => v['name'] as String).toList();
      } catch (e) {
        debugPrint('Error fetching Google voices: $e');
      }
    }
    List<String> openaiVoices = kOpenAIVoices;
    List<String> validVoices = providerName == 'google'
        ? googleVoices
        : openaiVoices;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_voice');
      if (saved != null && validVoices.contains(saved)) {
        effectiveVoice = saved;
      }
    } catch (_) {}
    final envDefault = Config.getOpenaiVoice();
    if (!validVoices.contains(effectiveVoice)) {
      effectiveVoice = validVoices.isNotEmpty
          ? validVoices.first
          : resolveDefaultVoice(envDefault);
    }
    _currentVoice = effectiveVoice;

    // Mostrar configuración de audio
    final ttsMode = Config.getAudioTtsMode().toLowerCase();
    final useGoogleVoice = _shouldUseGoogleVoiceSystem();

    if (useGoogleVoice) {
      debugPrint(
        '📞 Starting call with GOOGLE VOICE SYSTEM: Gemini AI + Google Cloud TTS/STT, voice: $_currentVoice',
      );
    } else {
      debugPrint(
        '📞 Starting continuous call with OpenAI Realtime: $model, voice: $_currentVoice',
      );
    }
    debugPrint('🔧 Audio config: provider=$providerName, tts_mode=$ttsMode');

    _callStartTime = DateTime.now();
    _callMessages.clear();
    _userSpoke = false;
    _aiResponded = false;
    _pendingAiTextSegments.clear();
    _subtitleRevealTimer?.cancel();
    _subtitleRevealIndex = 0;
    _fullAiText = '';
    _firstAudioReceived = false;
    _responseFailureCount = 0;

    // Mic diferido: no iniciamos captura hasta aceptación (start_call puro) o primer audio IA.
    _isMuted = true; // lógicamente silenciado
    _shouldMuteMic = true; // gate para no enviar nada todavía
    debugPrint('🎤 Mic diferido (esperando start_call puro o audio IA)');

    try {
      if (playRingback) {
        // Start ringback tone immediately
        debugPrint('🎵 Starting ringback tone...');
        await _startRingback();
        _ringbackActive = true;
        _ringbackStartAt = DateTime.now();
        // Timeout de seguridad para ringback
        Timer(Duration(milliseconds: _ringbackMaxMs), () {
          if (_ringbackActive && !_firstAudioReceived) {
            debugPrint('⏱️ Ringback timeout alcanzado, deteniendo tono');
            _stopRingback();
            _ringbackActive = false;
            _flushBufferedTextIfAny();
          }
        });
      }

      _client = di.getRealtimeClientForProvider(
        providerName,
        model: model ?? Config.requireDefaultTextModel(),
        onText: (textDelta) {
          if (_suppressFurtherAiText) {
            return; // no pasar más texto a la UI tras end_call
          }
          _uiOnText ??= onText;
          // Detectar inicio de una nueva respuesta AI (la anterior ya fue commit + playback terminó)
          if (!_aiMessagePendingCommit &&
              _currentAiResponseText.isNotEmpty &&
              !_isPlayingComplete) {
            if (_subtitleDebug) {
              debugPrint(
                '🔄 [SUB] Nueva respuesta detectada -> reset buffers subtítulos',
              );
            }
            _currentAiResponseText = '';
            _pendingAiTextSegments.clear();
            _fullAiText = '';
            _subtitleRevealTimer?.cancel();
            _subtitleRevealTimer = null;
            _subtitleRevealIndex = 0;
            _lastLoggedSubtitleChars = 0;
            // reset ratio (eliminado)
          }
          final seg = textDelta.replaceAll('\n', ' ').trim();
          if (seg.isEmpty) return;
          if (_subtitleDebug) {
            debugPrint('🔹 [SUB-RAW] "$seg"');
          }
          _mergeAiSegment(seg);
          _aiResponded = true;
          _aiMessagePendingCommit = true; // se añadirá al final
        },
        onAudio: (audioChunk) async {
          if (!_shouldMuteMic) {
            _shouldMuteMic = true; // gate mic once AI audio starts
            if (kDebugMode) debugPrint('🔇 Mic gated (AI audio)');
          }
          if (!_micStarted) {
            await ensureMicStarted();
            _isMuted = true; // seguimos muted mientras IA habla
            debugPrint('🎤 Mic iniciado (diferido) al recibir audio IA');
          }
          _handleStreamingAudioBytes(audioChunk);
          if (!_firstAudioReceived) {
            _firstAudioReceived = true;
            if (_ringbackActive) {
              final elapsed = DateTime.now()
                  .difference(_ringbackStartAt ?? DateTime.now())
                  .inMilliseconds;
              // Respetar duración mínima: si llega audio demasiado pronto, mantenemos ringback hasta _ringbackMinMs
              if (elapsed >= _ringbackMinMs) {
                debugPrint(
                  '🔔 Primer audio IA recibido -> detener ringback (elapsed=$elapsed ms >= min=$_ringbackMinMs ms)',
                );
                _stopRingback();
                _ringbackActive = false;
              } else {
                final waitMs = _ringbackMinMs - elapsed;
                debugPrint(
                  '🔔 Audio IA temprano ($elapsed ms). Mantener ringback $waitMs ms extra para 2-3 loops.',
                );
                Timer(Duration(milliseconds: waitMs), () {
                  if (_ringbackActive) {
                    debugPrint(
                      '🔔 Deteniendo ringback tras min ${_ringbackMinMs}ms',
                    );
                    _stopRingback();
                    _ringbackActive = false;
                  }
                });
              }
            }
            // Si no hay audio acumulado luego, fallback
          }
          // (legacy milestones eliminados)
        },
        onError: (error) {
          debugPrint('❌ Realtime client error: $error');
          final msg = error.toString();
          if (msg.contains('response_failed:')) {
            // Parsear código y mensaje
            final m = RegExp(r'response_failed:([^ ]*)\s*(.*)').firstMatch(msg);
            final code = (m != null ? m.group(1) : '')?.trim() ?? '';
            final detail = (m != null ? m.group(2) : '')?.trim() ?? '';
            final lowerCode = code.toLowerCase();
            final lowerDetail = detail.toLowerCase();
            String reasonCategory = 'model_server_error';
            if (lowerCode.contains('policy') ||
                lowerDetail.contains('policy') ||
                lowerDetail.contains('safety')) {
              reasonCategory = 'policy_violation';
            } else if (lowerCode.contains('rate') ||
                lowerDetail.contains('rate limit')) {
              reasonCategory = 'rate_limit';
            }
            if (reasonCategory == 'policy_violation') {
              // Detener inmediatamente (no reintentar)
              if (_ringbackActive) {
                try {
                  _stopRingback();
                } catch (_) {}
                _ringbackActive = false;
              }
              try {
                onHangupReason?.call('policy_violation');
              } catch (_) {}
              return;
            }
            _responseFailureCount++;
            final maxRetries = 2;
            final isFinal = _responseFailureCount > maxRetries;
            if (isFinal) {
              // Colgar con razón específica
              if (_ringbackActive) {
                try {
                  _stopRingback();
                } catch (_) {}
                _ringbackActive = false;
              }
              try {
                onHangupReason?.call(reasonCategory);
              } catch (_) {}
            } else {
              // Reintento suave: pedir nueva respuesta (mantener subtítulos intactos)
              final backoffMs = 200 + (_responseFailureCount * 250);
              debugPrint(
                '🔁 Reintentando respuesta tras fallo ($reasonCategory) intento=$_responseFailureCount en ${backoffMs}ms',
              );
              try {
                onRetryScheduled?.call(_responseFailureCount, backoffMs);
              } catch (_) {}
              Future.delayed(Duration(milliseconds: backoffMs), () {
                if (_client != null && _isConnected) {
                  _client!.requestResponse(audio: true, text: true);
                }
              });
            }
          }
          // Errores de conexión / socket genéricos (no response_failed)
          else {
            final lower = msg.toLowerCase();
            final isConn =
                lower.contains('socket') ||
                lower.contains('websocket') ||
                lower.contains('connection') ||
                lower.contains('network') ||
                lower.contains('handshake') ||
                lower.contains('timed out') ||
                lower.contains('timeout');
            if (isConn) {
              // Intento único de reconectar ligero si todavía no hubo audio ni conversación
              if (_responseFailureCount == 0 &&
                  !_firstAudioReceived &&
                  !_userSpoke) {
                debugPrint(
                  '🔌 Conexión perdida temprano -> intento reconexión suave en 400ms',
                );
                Future.delayed(const Duration(milliseconds: 400), () async {
                  if (_disposed) return;
                  try {
                    if (_client != null && !_client!.isConnected) {
                      await _client!.connect(
                        systemPrompt: systemPrompt,
                        voice: _currentVoice,
                        inputAudioFormat: 'pcm16',
                        outputAudioFormat: 'pcm16',
                        turnDetectionType: 'server_vad',
                        silenceDurationMs: 480,
                      );
                      _isConnected = true;
                      debugPrint('🔄 Reconexión completada');
                      return; // no colgar
                    }
                  } catch (e) {
                    debugPrint('❌ Falló reconexión: $e');
                  }
                  // Si falla reconexión, notificar hangup por conexión
                  try {
                    onHangupReason?.call('connection_error');
                  } catch (_) {}
                });
              } else {
                try {
                  onHangupReason?.call('connection_error');
                } catch (_) {}
              }
            }
          }
        },
        onUserTranscription: (transcription) {
          debugPrint('🎤 User transcription received: "$transcription"');
          final cleaned = _filterUserTranscript(transcription);
          if (cleaned != null) {
            _userSpoke = true;
            _callMessages.add(
              VoiceCallMessage(
                text: cleaned,
                isUser: true,
                timestamp: DateTime.now(),
              ),
            );
            onUserTranscription?.call(cleaned);
          } else {
            if (_subtitleDebug) {
              debugPrint('🚫 [TRANSCRIPT] Filtrado: "$transcription"');
            }
          }
        },
        onCompleted: () {
          debugPrint('🤖 AI response complete - starting playback');
          // Reintento diferido: si pedimos audio en fallback pero se omitió por respuesta activa
          if (_pendingSecondPhaseAudio &&
              !_firstAudioReceived &&
              _continuousAudioBuffer.isEmpty) {
            debugPrint(
              '🔁 Reintento segunda fase: primera respuesta terminó sin audio',
            );
            _pendingSecondPhaseAudio = false;
            Future.delayed(const Duration(milliseconds: 70), () {
              if (_client != null && _isConnected) {
                _client!.requestResponse(audio: true, text: true);
              }
            });
          }
          // Commit único del mensaje AI (texto consolidado)
          if (_aiMessagePendingCommit) {
            final txt = _currentAiResponseText.trim();
            if (txt.isNotEmpty) {
              _callMessages.add(
                VoiceCallMessage(
                  text: txt,
                  isUser: false,
                  timestamp: DateTime.now(),
                ),
              );
            }
            _aiMessagePendingCommit = false;
          }
          // Usar estrategia de reproducción basada en el proveedor
          final providerType = _getRealtimeProvider();
          final strategy = AudioPlaybackStrategyFactory.createStrategy(
            provider: providerType,
          );
          strategy.schedulePlayback(_playCompleteAudioFile);

          Log.d('Using ${providerType.name} audio playback strategy');
        },
      );

      await _client!.connect(
        systemPrompt: systemPrompt,
        voice: _currentVoice,
        inputAudioFormat: 'pcm16',
        outputAudioFormat: 'pcm16',
        // Usamos VAD del servidor para commits automáticos
        turnDetectionType: 'server_vad',
        silenceDurationMs: 480, // antes 700 (menor latencia de cierre de turno)
      );

      _isConnected = true;

      // Diferimos captura de micrófono hasta aceptación / primer audio IA
      await startStreaming();

      if (!suppressInitialAiRequest) {
        // Opción 1: fase inicial solo texto para permitir rechazo inmediato con etiqueta limpia
        if (twoPhaseInitial) {
          debugPrint(
            '🟢 Two-phase start: solicitando primera respuesta SOLO texto',
          );
          bool gotPureEndCall = false;
          bool gotPureStartCall = false;
          bool gotImplicitReject =
              false; // texto inesperado en lugar de start_call / end_call
          // Enlazar un listener temporal para detectar etiqueta pura rápida
          final completer = Completer<void>();
          void tempListener(String delta) {
            final t = delta.trim();
            if (t.isEmpty) return;
            if (t == '[end_call][/end_call]' ||
                t == '[end_call]' ||
                t == '[/end_call]') {
              gotPureEndCall = true;
              if (!completer.isCompleted) completer.complete();
              return;
            }
            if (t == '[start_call][/start_call]' ||
                t == '[start_call]' ||
                t == '[/start_call]') {
              gotPureStartCall = true;
              if (!completer.isCompleted) completer.complete();
              return;
            }
            // Cualquier otro texto en la PRIMERA respuesta (fase texto) implica que el modelo no siguió protocolo.
            // Requerimiento: tratarlo como si hubiese enviado end_call (rechazo).
            gotImplicitReject = true;
            gotPureEndCall = true; // forzar que no se solicite audio
            if (!completer.isCompleted) completer.complete();
          }

          // Re-asignar callback temporalmente (encapsulado)
          final originalUiOnText = _uiOnText; // podría ser null todavía
          _uiOnText = (s) {
            final beforeImplicit = gotImplicitReject;
            tempListener(s);
            final becameImplicit = !beforeImplicit && gotImplicitReject;
            // Solo reenviar a UI si NO se convirtió en rechazo implícito (para no mostrar texto basura)
            if (!becameImplicit) {
              try {
                if (originalUiOnText != null) originalUiOnText(s);
              } catch (_) {}
            }
          };
          _safeRequestResponse(
            audio: false,
            text: true,
            ctx: 'twoPhaseInitial-phase1',
          );
          // Esperar breve ventana para ver si el modelo emite la etiqueta pura (evitar bloquear indefinidamente)
          try {
            await completer.future.timeout(const Duration(milliseconds: 900));
          } catch (_) {}
          // Restaurar callback original (para no interceptar la segunda fase)
          _uiOnText = originalUiOnText;
          if (gotPureEndCall) {
            if (gotImplicitReject) {
              debugPrint(
                '� Primera respuesta inesperada (sin start_call puro) -> rechazo implícito simulado como end_call.',
              );
              // Enviar etiqueta end_call a la UI ahora que el callback original está restaurado
              try {
                onText('[end_call][/end_call]');
              } catch (_) {}
            } else {
              debugPrint(
                '🔴 Pure [end_call][/end_call] detectada en fase texto: no se pedirá audio.',
              );
              // BUGFIX: antes no se propagaba la etiqueta a la UI, impidiendo el colgado.
              // Inyectamos la etiqueta para que la UI ejecute la lógica de rechazo.
              try {
                onText('[end_call][/end_call]');
              } catch (_) {}
              // Detener ringback si seguía activo
              if (playRingback && _ringbackActive) {
                try {
                  await _stopRingback();
                  _ringbackActive = false;
                  debugPrint('🔕 Ringback detenido tras end_call temprano');
                } catch (_) {}
              }
            }
            // No se inicia segunda fase; la UI colgará al detectar etiqueta (inyectada o real).
          } else if (gotPureStartCall) {
            debugPrint(
              '🟢 start_call puro -> solicitando audio IA y activando mic (diferido)',
            );
            _safeRequestResponse(
              audio: true,
              text: true,
              ctx: 'twoPhaseInitial-start_call',
            );
            if (!_micStarted) {
              await ensureMicStarted();
              _isMuted =
                  false; // permitir hablar ya (gating se maneja con _shouldMuteMic)
              _shouldMuteMic =
                  true; // mantener gate hasta que IA termine primer turno
              debugPrint('🎤 Mic iniciado tras start_call puro');
            }
            if (playRingback) {
              debugPrint(
                '🎵 Ringback activo hasta primer audio o timeout (tras start_call)...',
              );
            }
          } else {
            // Timeout sin etiqueta alguna: continuar como antes pidiendo audio (modelo quizá hable directamente en audio)
            debugPrint(
              '🟡 Sin etiqueta start/end en fase inicial -> solicitando audio (fallback)',
            );
            _safeRequestResponse(
              audio: true,
              text: true,
              ctx: 'twoPhaseInitial-fallback-noTag',
            );
            // Marcar reintento diferido, asumimos que la respuesta seguía activa
            _pendingSecondPhaseAudio = true;
            if (playRingback) {
              debugPrint('🎵 Ringback activo hasta primer audio o timeout...');
            }
          }
        } else {
          // Comportamiento anterior (una sola petición audio+texto)
          debugPrint(
            '🎤 Starting AI response generation during ringback (single-phase)...',
          );
          _safeRequestResponse(
            audio: true,
            text: true,
            ctx: 'singlePhase-initial',
          );
          if (playRingback) {
            debugPrint('🎵 Ringback activo hasta primer audio o timeout...');
          }
        }
      } else {
        debugPrint(
          '⏳ Modo incoming: IA esperará primera intervención del usuario.',
        );
      }

      debugPrint('✅ Continuous call started successfully');

      // Print diagnostic info to help debug microphone issues
      await Future.delayed(const Duration(milliseconds: 1000));
      printMicrophoneStatus();
    } catch (e) {
      debugPrint('❌ Error starting continuous call: $e');
      rethrow;
    }
  }

  void setVoice(String voice) {
    _currentVoice = voice;
    debugPrint('🎵 Voice set to: $_currentVoice');
    if (_client != null && _isConnected) {
      try {
        _client!.updateVoice(voice);
      } catch (e) {
        debugPrint('⚠️ updateVoice seguro falló: $e');
      }
    } else {
      debugPrint('⚠️ updateVoice ignorado: cliente no conectado');
    }
  }

  // Solicita inmediatamente una respuesta con audio (se ignora si ya hay una activa)
  void requestImmediateAudioResponse({bool includeText = true}) {
    if (_client == null || !_isConnected) {
      debugPrint(
        '⚠️ requestImmediateAudioResponse ignorado: cliente nulo o desconectado',
      );
      return;
    }
    debugPrint(
      '⚡ Forzando requestResponse(audio: true, text: $includeText) tras start_call',
    );
    _safeRequestResponse(audio: true, text: includeText, ctx: 'immediateAudio');
  }

  // Activar supresión de texto AI (tras detección de end_call en cualquier capa)
  void suppressFurtherAiText() {
    if (!_suppressFurtherAiText) {
      debugPrint(
        '[AI-chan][VoiceCall] Supresión de texto AI activada (end_call)',
      );
      _suppressFurtherAiText = true;
    }
  }

  /// Obtiene el proveedor de realtime desde las variables de entorno
  RealtimeProvider _getRealtimeProvider() {
    final audioProvider = Config.getAudioProvider().toLowerCase();
    return RealtimeProviderHelper.fromString(audioProvider);
  }

  // ===== Wrappers seguros para requestResponse =====
  void _safeRequestResponse({
    required bool audio,
    required bool text,
    String ctx = 'unknown',
  }) {
    final c = _client;
    if (c == null) {
      debugPrint(
        '🚫 requestResponse($audio,$text) abortado: _client=null (ctx=$ctx)',
      );
      return;
    }
    if (!_isConnected) {
      debugPrint(
        '🚫 requestResponse($audio,$text) abortado: _isConnected=false (ctx=$ctx)',
      );
      return;
    }
    try {
      c.requestResponse(audio: audio, text: text);
    } catch (e, st) {
      debugPrint('❌ requestResponse fallo (ctx=$ctx): $e\n$st');
    }
  }

  // Detener inmediatamente cualquier reproducción de audio AI en curso (para ocultar pronunciación de end_call)
  Future<void> stopCurrentAiPlayback() async {
    try {
      if (_isPlayingComplete) {
        await _audioPlayer.stop();
        _isPlayingComplete = false;
        debugPrint(
          '[AI-chan][VoiceCall] Playback AI detenido inmediatamente por end_call',
        );
      }
      // Limpiar buffer restante para evitar que se reprograme
      _continuousAudioBuffer.clear();
    } catch (e) {
      debugPrint(
        '[AI-chan][VoiceCall] Error deteniendo playback inmediato: $e',
      );
    }
  }

  // Descartar audio acumulado antes de que se inicie playback (se invoca al detectar plain end_call durante generación)
  void discardPendingAiAudio() {
    if (_continuousAudioBuffer.isNotEmpty) {
      debugPrint(
        '[AI-chan][VoiceCall] Descartando audio AI acumulado (plain end_call) antes de reproducir',
      );
      _continuousAudioBuffer.clear();
    }
  }

  // Descarta cualquier texto AI acumulado hasta ahora si contiene artefactos de start_call.
  // Se usa cuando llega una etiqueta [start_call] con texto adicional que decidimos ignorar.
  void discardAiTextIfStartCallArtifact() {
    final hasStart =
        _currentAiResponseText.contains('[start_call') ||
        _pendingAiTextSegments.any((s) => s.contains('[start_call'));
    if (!hasStart) return;
    debugPrint(
      '🧽 Descargando buffer AI por start_call con texto (no se mostrará ni guardará)',
    );
    _currentAiResponseText = '';
    _pendingAiTextSegments.clear();
    _fullAiText = '';
  }

  // Salvage: si llega etiqueta start_call acompañada de texto (contaminada) igual la tomamos como aceptación
  // y disparamos (o programamos) la petición de audio. Replica la lógica del start_call puro pero
  // sin depender de que la respuesta actual haya terminado.
  Future<void> salvageStartCallAfterContaminatedTag() async {
    debugPrint('🛠️ Salvage start_call contaminado -> solicitar audio IA');
    // Si ya hay una response activa, marcaremos reintento diferido para que onCompleted vuelva a pedir audio
    _pendingSecondPhaseAudio = true;
    // Intento inmediato (será ignorado si _hasActiveResponse=true en el cliente)
    requestImmediateAudioResponse(includeText: true);
    // Iniciar mic diferido si aún no
    if (!_micStarted) {
      await ensureMicStarted();
      _isMuted =
          true; // mantener muted hasta que llegue el primer audio IA real
      _shouldMuteMic = true;
      debugPrint('🎤 Mic iniciado (salvage) a la espera de audio IA');
    }
  }

  VoiceCallSummary createCallSummary() {
    final now = DateTime.now();
    final startTime = _callStartTime ?? now;
    final duration = now.difference(startTime);

    return VoiceCallSummary(
      startTime: startTime,
      endTime: now,
      duration: duration,
      messages: List.from(_callMessages),
      userSpoke: _userSpoke,
      aiResponded: _aiResponded,
    );
  }

  void clearMessages() {
    debugPrint('🧹 Clearing messages');
    _continuousAudioBuffer.clear();
    _isPlayingComplete = false;
    _shouldMuteMic = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _callMessages.clear();
    _userSpoke = false;
    _aiResponded = false;
    _callStartTime = null;
  }

  // Send audio data to the API
  void sendAudio(Uint8List audioData) {
    if (_client != null && _isConnected && !_isMuted) {
      _client!.appendAudio(audioData);
    }
  }

  // ========== ULTRA-SIMPLE AUDIO STREAMING ==========

  // Start the ultra-simple audio system
  Future<void> startStreaming() async {
    if (_isStreaming) return;
    _isStreaming = true;

    debugPrint('📡 Ultra-simple streaming started');
    _startPlayback();
  }

  // Stop streaming
  Future<void> stopStreaming() async {
    _isStreaming = false;
    await _audioPlayer.stop();
    debugPrint('📡 Ultra-simple streaming stopped');
  }

  // Handle incoming audio bytes directly - collect for single file playback
  void _handleStreamingAudioBytes(Uint8List audioBytes) {
    if (!_isStreaming) return;

    try {
      // Avoid duplicate or empty audio chunks
      if (audioBytes.isEmpty) return;

      // Simply collect all audio data
      _continuousAudioBuffer.addAll(audioBytes);

      // Show progress every second of audio
      if (_continuousAudioBuffer.length % 24000 == 0) {
        debugPrint(
          '🎵 Collecting audio: ${_continuousAudioBuffer.length} bytes (${((_continuousAudioBuffer.length / 2) / 24000).toStringAsFixed(1)}s)',
        );
      }
      // Registrar metadatos de chunk (modo directo)
      final bytes = audioBytes.length;
      if (bytes > 0) {
        final startSamples = _totalOutputSamples;
        final newSamples = bytes >> 1; // /2 bytes por muestra
        _totalOutputSamples += newSamples;
        final endSamples = _totalOutputSamples;
        final startMs = (startSamples * 1000 / _lastOutputSampleRate).round();
        final endMs = (endSamples * 1000 / _lastOutputSampleRate).round();
        final meta = _AudioChunkMeta(
          index: _audioChunkMetas.length,
          startSamples: startSamples,
          endSamples: endSamples,
          startMs: startMs,
          endMs: endMs,
        );
        if (_audioChunkMetas.isEmpty && _preAudioTextBuffer != null) {
          final pre = _preAudioTextBuffer!.toString();
          if (pre.isNotEmpty) meta.text.write(pre);
          _preAudioTextBuffer = null;
        }
        _audioChunkMetas.add(meta);
      }
    } catch (e) {
      debugPrint('❌ Error collecting audio: $e');
    }
  }

  // Ultra-simple continuous playback - single file approach
  void _startPlayback() {
    // No longer needed - we wait for onCompleted callback to play complete file
    debugPrint(
      '📡 Ready to play complete audio files when AI finishes speaking',
    );
  }

  // Play the complete audio file when AI finishes speaking
  Future<void> _playCompleteAudioFile() async {
    if (!_isStreaming || _isPlayingComplete) return;

    if (_continuousAudioBuffer.isEmpty) {
      debugPrint('🔇 No audio data to play');
      _shouldMuteMic = false; // liberar mic si no hubo audio
      _flushBufferedTextIfAny();
      return;
    }

    // Asegurar que no solapamos la voz IA con el ringback: esperar a que termine (mínimo cumplido)
    if (_ringbackActive) {
      final elapsed = DateTime.now()
          .difference(_ringbackStartAt ?? DateTime.now())
          .inMilliseconds;
      if (elapsed < _ringbackMinMs) {
        final waitMs = _ringbackMinMs - elapsed;
        debugPrint(
          '⏳ Esperando fin ringback (${waitMs}ms restantes) antes de reproducir audio IA',
        );
        Timer(Duration(milliseconds: waitMs), () {
          // Forzar parada si sigue activo
          if (_ringbackActive) {
            _stopRingback();
            _ringbackActive = false;
          }
          // Reintentar reproducción
          _playCompleteAudioFile();
        });
        return; // salir; se retomará tras el delay
      } else {
        debugPrint(
          '🔔 Ringback activo pero mínimo alcanzado; detener antes de reproducir IA',
        );
        _stopRingback();
        _ringbackActive = false;
      }
    }

    _isPlayingComplete = true;

    try {
      debugPrint(
        '🎵 Playing complete audio file: ${_continuousAudioBuffer.length} bytes (${((_continuousAudioBuffer.length / 2) / 24000).toStringAsFixed(1)}s)',
      );
      if (_subtitleDebug) {
        debugPrint(
          '📊 [SUB] Preparando revelado. Segments=${_pendingAiTextSegments.length}',
        );
      }
      // Asegurar que haya un único segmento consolidado
      if (_pendingAiTextSegments.length > 1) {
        _pendingAiTextSegments
          ..clear()
          ..add(
            _currentAiResponseText.isNotEmpty
                ? _currentAiResponseText
                : _fullAiText,
          );
      }

      // Normalizar puntuación final antes de iniciar el revelado para evitar artefactos como "?.," o "!¿"
      if (_pendingAiTextSegments.isNotEmpty) {
        final cleaned = _finalizePunctuation(_pendingAiTextSegments.join(''));
        if (cleaned != _pendingAiTextSegments.first) {
          _pendingAiTextSegments
            ..clear()
            ..add(cleaned);
          _currentAiResponseText = cleaned;
        }
      }

      // Generate single complete WAV file
      final completeWavData = _generateSimpleWav(
        _continuousAudioBuffer,
        _lastOutputSampleRate,
      );
      final tempFile = await _writeToTempFile(completeWavData);

      debugPrint('🔊 Starting playback of complete audio file...');

      // Play the complete file
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      _audioStartedForCurrentResponse = true; // habilita subtítulos
      _isPlayingComplete = true;

      // Wait for playback to complete (estimate duration)
      final durationMs = (((_continuousAudioBuffer.length / 2) / 24000) * 1000)
          .round();
      debugPrint(
        '🕐 Audio playing in background for ${(durationMs / 1000).toStringAsFixed(1)}s...',
      );

      _playbackStartAt = DateTime.now();
      // Iniciar revelado progresivo de subtítulos sincronizado (si hay texto)
      _startSubtitleReveal(durationMs);
      // Permitir hablar antes: basado en progreso (65%) y duración mínima
      if (durationMs > 2500) {
        final earlyMs = (durationMs * _earlyUnmuteProgress)
            .clamp(1200, durationMs - 400)
            .toInt();
        if (_subtitleDebug) {
          debugPrint(
            '🎤 [SUB] Early unmute programado en $earlyMs ms (${(_earlyUnmuteProgress * 100).toStringAsFixed(0)}% aprox)',
          );
        }
        Timer(Duration(milliseconds: earlyMs), () {
          if (_isPlayingComplete) {
            _shouldMuteMic = false; // gate off
            _isMuted = false; // permitir hablar
            debugPrint(
              '🎤 Mic ungated (progress ${(earlyMs / durationMs * 100).toStringAsFixed(1)}%) - usuario puede hablar',
            );
          }
        });
      } else if (durationMs <= 1200) {
        // respuestas muy cortas: liberar justo tras terminar para evitar eco
      }

      // Set timer to cleanup when playback should be done
      _playbackTimer = Timer(Duration(milliseconds: durationMs + 200), () {
        debugPrint('🎵 Complete audio playback finished');
        _isPlayingComplete = false;
        _audioStartedForCurrentResponse =
            false; // cerrar gating para siguiente respuesta
        _continuousAudioBuffer.clear();
        _shouldMuteMic = false;
        _isMuted = false;
        debugPrint('🎤 Mic ungated after playback (fin respuesta)');
        // Ya no forzamos revelar todo aquí: dejamos que el timer de subtítulos termine
        // su recorrido con el lag (_subtitleLagMs). El mensaje AI ya se puede commitear
        // porque _fullAiText contiene el total.
      });
    } catch (e) {
      debugPrint('❌ Error playing complete audio: $e');
      _isPlayingComplete = false;
      _shouldMuteMic = false;
      _emitFullSubtitleIfPending();
    }
  }

  void _startSubtitleReveal(int durationMs) {
    if (_pendingAiTextSegments.isEmpty || _uiOnText == null) return;
    // No iniciar revelado si aún no comenzó audio real (evita subtítulos "silenciosos")
    if (!_audioStartedForCurrentResponse) {
      if (_subtitleDebug) {
        debugPrint(
          '⏸️ [SUB] Bloqueado inicio revelado: audio aún no ha comenzado',
        );
      }
      return;
    }
    _fullAiText = _pendingAiTextSegments.join('');
    final totalChars = _fullAiText.length;
    if (totalChars == 0) return;
    // En modo directo reducimos lag para que vaya prácticamente a la par.
    _subtitleLagMs = totalChars < 30 ? 120 : 200; // lag adaptativo directo
    _subtitleRevealIndex = 0;
    // Antes se limpiaba a cadena vacía, produciendo "desaparición" de los primeros cachos.
    // Lo evitamos para no generar parpadeo: dejamos el texto ya mostrado hasta el primer tick.
    _subtitleRevealTimer?.cancel();
    // Notificar a la UI que comienza modo revelado progresivo (sentinel no visible)
    try {
      _uiOnText?.call('__REVEAL__');
    } catch (_) {}
    if (durationMs < 600) {
      // audio muy corto -> mostrar todo
      _emitUiTextSafely(_fullAiText);
      if (_subtitleDebug) {
        debugPrint(
          '⚡ [SUB] Audio corto (${durationMs}ms). Mostrar todo ($totalChars chars)',
        );
      }
      return;
    }
    if (_subtitleDebug) {
      debugPrint(
        '🚀 [SUB] Inicio revelado sincronizado por hitos totalChars=$totalChars audioMs=$durationMs tick=40ms',
      );
    }
    _lastLoggedSubtitleChars = 0;
    // ratio log eliminado
    const tickMs = 40; // más fluido y rápido
    // (milestones legacy eliminados)
    // Parámetros de pacing para modo directo
    const directTickLeadMs =
        90; // adelanto máximo permitido sobre el audio real
    _subtitleRevealTimer = Timer.periodic(const Duration(milliseconds: tickMs), (
      t,
    ) {
      if (_playbackStartAt == null) return;
      final elapsed = DateTime.now()
          .difference(_playbackStartAt!)
          .inMilliseconds;
      if (elapsed < _subtitleLagMs) return; // esperar lag
      final audioAlignedTime =
          elapsed - _subtitleLagMs; // ms de audio efectivamente reproducidos
      int targetChars;
      // Pacing proporcional global: evita bursts ligados a asignar todo un delta a un único chunk.
      final effectiveTime = math.min(
        audioAlignedTime + directTickLeadMs,
        durationMs,
      );
      final ratio = durationMs <= 0
          ? 1.0
          : (effectiveTime / durationMs).clamp(0.0, 1.0);
      targetChars = (ratio * totalChars).floor();
      if (targetChars < _subtitleRevealIndex) {
        targetChars = _subtitleRevealIndex; // nunca retroceder
      }
      final maxGrow = 28; // hard cap para no saltar de golpe textos muy largos
      if (targetChars > _subtitleRevealIndex + maxGrow) {
        targetChars = _subtitleRevealIndex + maxGrow;
      }
      // Clamp absoluto contra longitud actual (por si se acortó inesperadamente)
      final safeTotal = _fullAiText.length;
      if (targetChars > safeTotal) targetChars = safeTotal;
      if (targetChars > _subtitleRevealIndex) {
        _subtitleRevealIndex = targetChars;
        try {
          final end = _subtitleRevealIndex.clamp(0, _fullAiText.length);
          _emitUiTextSafely(_fullAiText.substring(0, end));
        } catch (e) {
          if (_subtitleDebug) debugPrint('⚠️ [SUB] substring error (tick): $e');
        }
        if (_subtitleDebug) {
          String snippet;
          try {
            final end = _subtitleRevealIndex.clamp(0, _fullAiText.length);
            snippet = _fullAiText.substring(0, end).replaceAll('\n', ' ');
          } catch (_) {
            snippet = '[range-error]';
          }
          final advancedEnough =
              _subtitleRevealIndex - _lastLoggedSubtitleChars >= 12;
          if (advancedEnough || _subtitleRevealIndex == totalChars) {
            debugPrint(
              '📝 [SUB][sync] chars=$_subtitleRevealIndex/$totalChars time=$audioAlignedTime/$durationMs ms "$snippet"',
            );
            _lastLoggedSubtitleChars = _subtitleRevealIndex;
          }
        }
      }
      if (_subtitleRevealIndex >= totalChars) {
        t.cancel();
        _subtitleRevealTimer = null;
        if (_subtitleRevealIndex < totalChars) {
          _subtitleRevealIndex = totalChars;
          try {
            _emitUiTextSafely(_fullAiText);
          } catch (e) {
            if (_subtitleDebug) debugPrint('⚠️ [SUB] final emit error: $e');
          }
        }
        if (_subtitleDebug) {
          debugPrint('🏁 [SUB] Revelado completo (proporcional)');
        }
      }
    });
  }

  void _updateOngoingSubtitleReveal() {
    if (_subtitleRevealTimer == null || _playbackStartAt == null) return;
    final newFull = _pendingAiTextSegments.join('');
    if (newFull.length == _fullAiText.length) return; // nada nuevo
    final oldLen = _fullAiText.length;
    _fullAiText = newFull; // ampliar texto completo
    // Recalcular ratio usando tiempo transcurrido vs duración programada (estimada en inicio)
    // Nota: mantenemos la misma duración objetivo inicial: _subtitleRevealTimer sigue
    // Al siguiente tick el cálculo usará el totalChars ampliado
    if (_subtitleDebug) {
      debugPrint(
        '🔄 [SUB] Texto ampliado durante revelado old=$oldLen new=${_fullAiText.length}',
      );
    }
  }

  // ===== Consolidación de segmentos AI =====
  void _mergeAiSegment(String seg) {
    // Simplificado: normalizar, y si el nuevo segmento es más largo (o incluye al actual) reemplazarlo, sino ignorar.
    final prevLen = _currentAiResponseText.length;
    seg = seg.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (seg.contains('....')) seg = seg.replaceAll(RegExp(r'\.{4,}'), '...');
    if (seg.isEmpty) return;
    if (seg.length >= _currentAiResponseText.length ||
        seg.contains(_currentAiResponseText)) {
      _currentAiResponseText = seg;
    }
    _pendingAiTextSegments
      ..clear()
      ..add(_currentAiResponseText);
    if (_subtitleDebug) {
      debugPrint('� [SUB-BUF][simple] len=${_currentAiResponseText.length}');
    }
    final newLen = _currentAiResponseText.length;
    if (newLen > prevLen) {
      final delta = _currentAiResponseText.substring(prevLen, newLen);
      if (_audioChunkMetas.isEmpty) {
        (_preAudioTextBuffer ??= StringBuffer()).write(delta);
      } else {
        _audioChunkMetas.last.text.write(delta);
      }
    }
    if (_subtitleRevealTimer != null && _isPlayingComplete) {
      _updateOngoingSubtitleReveal();
    }
  }

  // Normaliza secuencias de puntuación, espacios y corrige duplicados.
  String _finalizePunctuation(String input) {
    String out = input;
    // Añadir espacio después de ! o ? si viene un signo de apertura inverso sin espacio: "!¿" -> "! ¿"
    out = out.replaceAllMapped(RegExp(r'([!\?])¿'), (m) => '${m.group(1)} ¿');
    // Quitar puntos duplicados salvo si es una elipsis de 3 puntos (mantener "...")
    out = out.replaceAllMapped(
      RegExp(r'([^\.])\.{2}(?!\.)'),
      (m) => '${m.group(1)}.',
    ); // dos puntos -> uno
    out = out.replaceAllMapped(
      RegExp(r'([\.\!\?])\s*\.'),
      (m) => m.group(1)!,
    ); // "?." -> "?"
    // Asegurar espacio después de ! ? . si luego viene letra o signo de apertura español
    out = out.replaceAllMapped(RegExp(r'([!\?\.])(\S)'), (m) {
      final punct = m.group(1)!;
      final next = m.group(2)!;
      if ('¡¿,'.contains(next)) return '$punct $next';
      if (RegExp(r'[A-ZÁÉÍÓÚÑa-záéíóúñ]').hasMatch(next)) return '$punct $next';
      return m.group(0)!;
    });
    // Quitar espacio antes de signos de puntuación simples
    out = out.replaceAllMapped(RegExp(r'\s+([,;:])'), (m) => m.group(1)!);
    // Compactar espacios múltiples
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    // Limpiar espacios antes de signos finales
    out = out.replaceAll(RegExp(r' \?'), ' ?').replaceAll(RegExp(r' !'), ' !');
    return out.trim();
  }

  // ===== Filtrado de transcripciones de usuario =====
  final List<RegExp> _bannedTranscriptPatterns = [
    // Frases típicas que aparecen erróneamente por modelos entrenados con videos
    RegExp(r'Subt[ií]tulos por la comunidad de Amara', caseSensitive: false),
    RegExp(r'Subt[ií]tulos generados autom[aá]ticamente', caseSensitive: false),
    RegExp(r'Suscr[ií]bete', caseSensitive: false),
    RegExp(r'No olvides suscribirte', caseSensitive: false),
    RegExp(r'Dale like', caseSensitive: false),
    RegExp(r'Activa la campanita', caseSensitive: false),
    RegExp(r'Comparte el video', caseSensitive: false),
    RegExp(r'Ap[oó]yanos con un like', caseSensitive: false),
    RegExp(r'^¿?Viemos\??$', caseSensitive: false),
  ];
  String? _filterUserTranscript(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    for (final p in _bannedTranscriptPatterns) {
      if (p.hasMatch(t)) return null; // descartar frase típica irrelevante
    }
    // Permitir muletillas/fillers cortos comunes que ayudan a no recortar inicio de turno
    const fillers = {'m', 'mm', 'mmm', 'eh', 'ehm', 'em', 'hm', 'uh', 'ah'};
    if (t.length <= 2 && !RegExp(r'[aeiouáéíóú]').hasMatch(t.toLowerCase())) {
      if (!fillers.contains(t.toLowerCase())) return null;
    }
    return t;
  }

  void _emitFullSubtitleIfPending() {
    if (_disposed) return;
    if (_uiOnText != null && _fullAiText.isNotEmpty) {
      _emitUiTextSafely(_fullAiText);
    } else if (_uiOnText != null && _pendingAiTextSegments.isNotEmpty) {
      _emitUiTextSafely(_pendingAiTextSegments.join(''));
    }
    _pendingAiTextSegments.clear();
  }

  void _flushBufferedTextIfAny() {
    if (_pendingAiTextSegments.isNotEmpty && _uiOnText != null) {
      _emitFullSubtitleIfPending();
    }
  }

  // Generate WAV header - ultra simple
  Uint8List _generateSimpleWav(List<int> pcmData, int sampleRate) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    final wav = BytesBuilder();

    // RIFF header
    wav.add('RIFF'.codeUnits);
    wav.add(_intToBytes(fileSize, 4));
    wav.add('WAVE'.codeUnits);

    // fmt chunk
    wav.add('fmt '.codeUnits);
    wav.add(_intToBytes(16, 4)); // chunk size
    wav.add(_intToBytes(1, 2)); // audio format (PCM)
    wav.add(_intToBytes(channels, 2));
    wav.add(_intToBytes(sampleRate, 4));
    wav.add(_intToBytes(byteRate, 4));
    wav.add(_intToBytes(blockAlign, 2));
    wav.add(_intToBytes(bitsPerSample, 2));

    // data chunk
    wav.add('data'.codeUnits);
    wav.add(_intToBytes(dataSize, 4));
    wav.add(pcmData);

    return Uint8List.fromList(wav.toBytes());
  }

  List<int> _intToBytes(int value, int bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes; i++) {
      result.add((value >> (8 * i)) & 0xFF);
    }
    return result;
  }

  Future<File> _writeToTempFile(Uint8List data) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(data);
    return file;
  }

  void dispose() {
    _disposed = true;
    _stopMicrophoneCapture();
    _audioPlayer.dispose();
    _ringPlayer.dispose();
    _recorder?.dispose();
    _micLevelController.close();
    _playbackTimer?.cancel();
    try {
      _subtitleRevealTimer?.cancel();
    } catch (_) {}
    _uiOnText = null; // liberar callback para GC
  }

  // ====== Emisión segura a la UI (previene TypeError por null check) ======
  void _emitUiTextSafely(String text) {
    // Gating adicional: si no hay audio en curso (o aún no inició para esta respuesta) y no es sentinel, bloquear
    if (text != '__REVEAL__' && !_audioStartedForCurrentResponse) {
      if (_subtitleDebug) {
        debugPrint('🚫 [SUB] Bloqueado texto sin audio: len=${text.length}');
      }
      return;
    }
    if (_disposed) return; // no emitir tras dispose
    if (_suppressFurtherAiText) return; // suprimido por protocolo end_call
    final cb = _uiOnText;
    if (cb == null) return;
    try {
      cb(text);
    } catch (e, st) {
      debugPrint('⚠️ Error emitiendo texto UI: $e\n$st');
    }
  }

  // ==== API de depuración / análisis: obtener mapeo aproximado audio<->subtítulos ====
  // Devuelve una lista de chunks con startMs/endMs (timeline del audio IA reproducido) y el texto asociado.
  // Se basa en los milestones acumulados (audioMs acumulado vs chars totales) y por tanto es aproximado:
  //  - Asume que la distribución temporal de caracteres entre dos milestones es uniforme (no fonema exacto).
  //  - Si se requiere precisión fonética habría que usar alineación forzada (MFA/Gentle) tras tener el WAV completo.
  List<SubtitleAudioChunk> buildSubtitleAudioChunks() {
    final chunks = <SubtitleAudioChunk>[];
    int globalCharCursor = 0;
    for (final m in _audioChunkMetas) {
      final txt = m.text.toString();
      if (txt.isEmpty) continue;
      final startChar = globalCharCursor;
      final endChar = startChar + txt.length;
      globalCharCursor = endChar;
      chunks.add(
        SubtitleAudioChunk(
          startMs: m.startMs,
          endMs: m.endMs,
          text: txt,
          startCharIndex: startChar,
          endCharIndex: endChar,
        ),
      );
    }
    // Fusionar trozos muy cortos (<60ms) con anterior para estabilidad
    final merged = <SubtitleAudioChunk>[];
    for (final c in chunks) {
      if (merged.isNotEmpty && c.durationMs < 60) {
        final last = merged.removeLast();
        merged.add(last.mergeWith(c));
      } else {
        merged.add(c);
      }
    }
    return merged;
  }

  /// Determina si debe usar el sistema de Google Voice (Gemini AI + Google Cloud TTS/STT)
  bool _shouldUseGoogleVoiceSystem() {
    final provider = _getRealtimeProvider();
    final ttsMode = Config.getAudioTtsMode().toLowerCase();
    return provider == RealtimeProvider.gemini && ttsMode == 'google';
  }
}

// Metadatos de un chunk de audio recibido (PCM) y el texto asociado durante su recepción
class _AudioChunkMeta {
  final int index;
  final int startSamples;
  final int endSamples;
  final int startMs;
  final int endMs;
  final StringBuffer text = StringBuffer();
  _AudioChunkMeta({
    required this.index,
    required this.startSamples,
    required this.endSamples,
    required this.startMs,
    required this.endMs,
  });
}

// Representa un trozo de subtítulo y su intervalo de audio aproximado
class SubtitleAudioChunk {
  final int startMs;
  final int endMs;
  final String text;
  final int startCharIndex;
  final int endCharIndex;
  int get durationMs => endMs - startMs;
  const SubtitleAudioChunk({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.startCharIndex,
    required this.endCharIndex,
  });

  SubtitleAudioChunk mergeWith(SubtitleAudioChunk other) {
    return SubtitleAudioChunk(
      startMs: startMs,
      endMs: other.endMs,
      text: text + other.text,
      startCharIndex: startCharIndex,
      endCharIndex: other.endCharIndex,
    );
  }

  @override
  String toString() =>
      'SubtitleAudioChunk([$startMs-$endMs ms,$durationMs ms] chars=$startCharIndex..$endCharIndex "$text")';
}
