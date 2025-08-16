import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:record/record.dart';

import '../services/openai_service.dart';
import '../services/openai_realtime_client.dart';
import '../services/tone_service.dart';
import '../models/message.dart';

class VoiceCallController {
  final OpenAIService openAIService;
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
  bool _shouldMuteMic = false; // micrófono gateado mientras AI habla/genera
  Timer? _playbackTimer;
  Timer? _subtitleRevealTimer;
  int _subtitleRevealIndex = 0; // índice de caracteres ya mostrados
  String _fullAiText = '';
  Function(String)? _uiOnText; // referencia al callback UI original
  bool _firstAudioReceived = false;
  bool _ringbackActive = false;
  static const int _ringbackMaxMs = 8000; // tope máximo
  static const int _ringbackMinMs = 5500; // asegurar 2-3 loops (~2.5s cada) antes de cortar
  // Eliminamos ringback mínimo rígido para evitar solapes con voz AI; se detendrá al primer audio.
  DateTime? _ringbackStartAt;
  DateTime? _playbackStartAt;
  static const double _earlyUnmuteProgress = 0.65; // permitir hablar al 65% del audio
  // Debug subtítulos
  final bool _subtitleDebug = false; // desactivado: logs de subtítulos silenciados
  int _lastLoggedSubtitleChars = 0;
  // Latencia artificial para que los subtítulos vayan detrás del audio simulando procesamiento.
  int _subtitleLagMs = 1000; // ajustable (reducido en modo directo)
  // Ya no usamos milestones heurísticos; pacing proporcional directo.

  // Estado de conexión
  OpenAIRealtimeClient? _client;
  bool _isConnected = false;
  bool _isMuted = false; // estado actual de mute (usuario)
  String _currentVoice = 'alloy';

  // Captura de audio
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;

  // Seguimiento de la llamada (para resumen)
  DateTime? _callStartTime;
  final List<VoiceCallMessage> _callMessages = [];
  bool _userSpoke = false;
  bool _aiResponded = false;
  // Auto-gain para mejorar claridad de ASR
  final bool _enableMicAutoGain = true;
  // Parámetros AGC (auto gain control) adaptativo
  final double _agcTargetRms = 0.18; // objetivo un poco más alto para que no tengas que alzar la voz
  final double _agcMaxGain = 5.0; // permitir más amplificación (antes 3x)
  double _agcNoiseFloorRms = 0.0; // estimación de ruido de fondo
  final double _agcNoiseFloorAlpha = 0.05; // suavizado del ruido
  final double _agcAttack = 0.35; // rapidez aumentando ganancia
  final double _agcRelease = 0.08; // rapidez reduciendo ganancia
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
        _agcNoiseFloorRms = _agcNoiseFloorRms * (1 - _agcNoiseFloorAlpha) + rms * _agcNoiseFloorAlpha;
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
    double noiseRatio = (_agcNoiseFloorRms > 0) ? (_agcNoiseFloorRms / rms).clamp(0.0, 1.0) : 0.0;
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

  VoiceCallController({required this.openAIService}) {
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
        debugPrint('🎤 Mic ungated after playback (fin respuesta - audio real)');
      }
    });
  }

  // ========== MICROPHONE CAPTURE ==========

  Future<void> _startMicrophoneCapture() async {
    debugPrint('🎤 Starting microphone capture (simple)...');
    _recorder ??= AudioRecorder();
    try {
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        debugPrint('❌ Microphone permission denied');
        return;
      }
      final stream = await _recorder!.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
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
      debugPrint('🎤 Microphone capture started (simple)');
    } catch (e) {
      debugPrint('❌ Error starting microphone: $e');
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
    debugPrint(effectivelyMuted ? '⚠️ MICROPHONE EFFECTIVELY MUTED' : '✅ MICROPHONE ACTIVE');
  }

  Future<void> stop({bool keepFxPlaying = false}) async {
    debugPrint('🛑 Stopping VoiceCallController (keepFxPlaying: $keepFxPlaying)');
    _shouldMuteMic = false;
    await _stopMicrophoneCapture();
    await stopStreaming();
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
      final hangupToneWav = ToneService.buildHangupOrErrorToneWav(sampleRate: _lastOutputSampleRate, durationMs: 500);

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

  Future<void> playNoAnswerTone({Duration duration = const Duration(seconds: 6)}) async {
    try {
      await _startRingback();
      await Future.delayed(duration);
      await _stopRingback();
      debugPrint('📞 Playing melodic no answer tone for ${duration.inSeconds}s');
    } catch (e) {
      debugPrint('Error playing no answer tone: $e');
      await Future.delayed(duration); // Fallback
    }
  }

  Future<void> _startRingback() async {
    try {
      final ringbackWav = ToneService.buildMelodicRingbackWav(sampleRate: _lastOutputSampleRate);

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
    Function(String)? onUserTranscription, // Nuevo callback para transcripciones del usuario
    dynamic recorder, // Para compatibilidad
    String model = 'gpt-4o-mini-realtime',
    String voice = 'alloy',
  }) async {
    debugPrint('📞 Starting continuous call with model: $model, voice: $voice');
    _currentVoice = voice;
    _callStartTime = DateTime.now();
    _callMessages.clear();
    _userSpoke = false;
    _aiResponded = false;
    _pendingAiTextSegments.clear();
    _subtitleRevealTimer?.cancel();
    _subtitleRevealIndex = 0;
    _fullAiText = '';
    _firstAudioReceived = false;

    // Micrófono activo desde el principio para no perder la primera palabra del usuario.
    _isMuted = false;
    _shouldMuteMic = false;
    debugPrint('🎤 Mic activo desde inicio (no se pierde primera palabra usuario)');

    try {
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

      _client = OpenAIRealtimeClient(
        model: 'gpt-4o-realtime-preview',
        onText: (textDelta) {
          _uiOnText ??= onText;
          // Detectar inicio de una nueva respuesta AI (la anterior ya fue commit + playback terminó)
          if (!_aiMessagePendingCommit && _currentAiResponseText.isNotEmpty && !_isPlayingComplete) {
            if (_subtitleDebug) {
              debugPrint('🔄 [SUB] Nueva respuesta detectada -> reset buffers subtítulos');
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
        onAudio: (audioChunk) {
          if (!_shouldMuteMic) {
            _shouldMuteMic = true; // gate mic once AI audio starts
            if (kDebugMode) debugPrint('🔇 Mic gated (AI audio)');
          }
          _handleStreamingAudioBytes(audioChunk);
          if (!_firstAudioReceived) {
            _firstAudioReceived = true;
            if (_ringbackActive) {
              final elapsed = DateTime.now().difference(_ringbackStartAt ?? DateTime.now()).inMilliseconds;
              // Respetar duración mínima: si llega audio demasiado pronto, mantenemos ringback hasta _ringbackMinMs
              if (elapsed >= _ringbackMinMs) {
                debugPrint(
                  '🔔 Primer audio IA recibido -> detener ringback (elapsed=$elapsed ms >= min=$_ringbackMinMs ms)',
                );
                _stopRingback();
                _ringbackActive = false;
              } else {
                final waitMs = _ringbackMinMs - elapsed;
                debugPrint('🔔 Audio IA temprano ($elapsed ms). Mantener ringback $waitMs ms extra para 2-3 loops.');
                Timer(Duration(milliseconds: waitMs), () {
                  if (_ringbackActive) {
                    debugPrint('🔔 Deteniendo ringback tras min ${_ringbackMinMs}ms');
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
        },
        onUserTranscription: (transcription) {
          debugPrint('🎤 User transcription received: "$transcription"');
          final cleaned = _filterUserTranscript(transcription);
          if (cleaned != null) {
            _userSpoke = true;
            _callMessages.add(VoiceCallMessage(text: cleaned, isUser: true, timestamp: DateTime.now()));
            onUserTranscription?.call(cleaned);
          } else {
            if (_subtitleDebug) {
              debugPrint('🚫 [TRANSCRIPT] Filtrado: "$transcription"');
            }
          }
        },
        onCompleted: () {
          debugPrint('🤖 AI response complete - starting playback');
          // Commit único del mensaje AI (texto consolidado)
          if (_aiMessagePendingCommit) {
            final txt = _currentAiResponseText.trim();
            if (txt.isNotEmpty) {
              _callMessages.add(VoiceCallMessage(text: txt, isUser: false, timestamp: DateTime.now()));
            }
            _aiMessagePendingCommit = false;
          }
          Timer(const Duration(milliseconds: 40), () => _playCompleteAudioFile());
        },
      );

      await _client!.connect(
        systemPrompt: systemPrompt,
        voice: voice,
        inputAudioFormat: 'pcm16',
        outputAudioFormat: 'pcm16',
        // Usamos VAD del servidor para commits automáticos
        turnDetectionType: 'server_vad',
        silenceDurationMs: 700,
      );

      _isConnected = true;

      // Start audio input capture BEFORE stopping ringback
      await _startMicrophoneCapture();
      await startStreaming();

      // Iniciar IA mientras suena ringback
      debugPrint('🎤 Starting AI response generation during ringback...');
      if (_client != null) {
        // Trigger AI to start conversation with a greeting DURING ringback
        _client!.requestResponse(audio: true, text: true);
      }
      debugPrint('🎵 Ringback activo hasta primer audio o timeout...');

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
      _client!.updateVoice(voice);
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
    debugPrint('📡 Ready to play complete audio files when AI finishes speaking');
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
      final elapsed = DateTime.now().difference(_ringbackStartAt ?? DateTime.now()).inMilliseconds;
      if (elapsed < _ringbackMinMs) {
        final waitMs = _ringbackMinMs - elapsed;
        debugPrint('⏳ Esperando fin ringback (${waitMs}ms restantes) antes de reproducir audio IA');
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
        debugPrint('🔔 Ringback activo pero mínimo alcanzado; detener antes de reproducir IA');
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
        debugPrint('📊 [SUB] Preparando revelado. Segments=${_pendingAiTextSegments.length}');
      }
      // Asegurar que haya un único segmento consolidado
      if (_pendingAiTextSegments.length > 1) {
        _pendingAiTextSegments
          ..clear()
          ..add(_currentAiResponseText.isNotEmpty ? _currentAiResponseText : _fullAiText);
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
      final completeWavData = _generateSimpleWav(_continuousAudioBuffer, _lastOutputSampleRate);
      final tempFile = await _writeToTempFile(completeWavData);

      debugPrint('🔊 Starting playback of complete audio file...');

      // Play the complete file
      await _audioPlayer.play(DeviceFileSource(tempFile.path));

      // Wait for playback to complete (estimate duration)
      final durationMs = (((_continuousAudioBuffer.length / 2) / 24000) * 1000).round();
      debugPrint('🕐 Audio playing in background for ${(durationMs / 1000).toStringAsFixed(1)}s...');

      _playbackStartAt = DateTime.now();
      // Iniciar revelado progresivo de subtítulos sincronizado (si hay texto)
      _startSubtitleReveal(durationMs);
      // Permitir hablar antes: basado en progreso (65%) y duración mínima
      if (durationMs > 2500) {
        final earlyMs = (durationMs * _earlyUnmuteProgress).clamp(1200, durationMs - 400).toInt();
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
      _uiOnText!(_fullAiText);
      if (_subtitleDebug) {
        debugPrint('⚡ [SUB] Audio corto (${durationMs}ms). Mostrar todo ($totalChars chars)');
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
    const directTickLeadMs = 90; // adelanto máximo permitido sobre el audio real
    _subtitleRevealTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (_playbackStartAt == null) return;
      final elapsed = DateTime.now().difference(_playbackStartAt!).inMilliseconds;
      if (elapsed < _subtitleLagMs) return; // esperar lag
      final audioAlignedTime = elapsed - _subtitleLagMs; // ms de audio efectivamente reproducidos
      int targetChars;
      // Pacing proporcional global: evita bursts ligados a asignar todo un delta a un único chunk.
      final effectiveTime = math.min(audioAlignedTime + directTickLeadMs, durationMs);
      final ratio = durationMs <= 0 ? 1.0 : (effectiveTime / durationMs).clamp(0.0, 1.0);
      targetChars = (ratio * totalChars).floor();
      if (targetChars < _subtitleRevealIndex) targetChars = _subtitleRevealIndex; // nunca retroceder
      final maxGrow = 28; // hard cap para no saltar de golpe textos muy largos
      if (targetChars > _subtitleRevealIndex + maxGrow) targetChars = _subtitleRevealIndex + maxGrow;
      if (targetChars > _subtitleRevealIndex) {
        _subtitleRevealIndex = targetChars;
        _uiOnText!(_fullAiText.substring(0, _subtitleRevealIndex));
        if (_subtitleDebug) {
          final snippet = _fullAiText.substring(0, _subtitleRevealIndex).replaceAll('\n', ' ');
          final advancedEnough = _subtitleRevealIndex - _lastLoggedSubtitleChars >= 12;
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
          _uiOnText!(_fullAiText);
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
      debugPrint('🔄 [SUB] Texto ampliado durante revelado old=$oldLen new=${_fullAiText.length}');
    }
  }

  // ===== Consolidación de segmentos AI =====
  void _mergeAiSegment(String seg) {
    final prevLenBeforeMerge = _currentAiResponseText.length;
    // Normalizar espacios y puntuación básica
    String norm(String s) => s
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ,', ',')
        .replaceAll(' .', '.')
        .replaceAll(' !', '!')
        .replaceAll(' ?', '?')
        .replaceAll(' ¡', '¡')
        .replaceAll(' ¿', '¿')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    seg = norm(seg);
    // Colapsar secuencias largas de puntos generadas como placeholders a una sola elipsis '...'
    if (seg.contains('....')) {
      seg = seg.replaceAll(RegExp(r'\.{4,}'), '...');
    }
    if (seg.isEmpty) return;

    // Si está vacío actual, asignar
    if (_currentAiResponseText.isEmpty) {
      _currentAiResponseText = seg;
    } else {
      final current = _currentAiResponseText;
      // Función para comparar ignorando espacios y puntuación ligera
      String strip(String s) => s.replaceAll(RegExp(r'[\s.,;:!?¡¿]'), '').toLowerCase();
      final curStr = strip(current);
      final newStr = strip(seg);

      // 1. Igual (quizá solo cambia espacios/puntuación) => reemplazar
      if (curStr == newStr) {
        _currentAiResponseText = seg;
      }
      // 2. Nuevo contiene al anterior => reemplazo (extensión/corrección)
      else if (newStr.contains(curStr)) {
        _currentAiResponseText = seg;
      }
      // 3. Anterior contiene nuevo => ignorar fragmento redundante
      else if (curStr.contains(newStr)) {
        // ignore
      } else {
        // 3b. Heurística: nuevo es casi un superset difuso del anterior (old como subsecuencia con pocas inserciones)
        bool fuzzySuperset(String oldS, String newS) {
          int i = 0, j = 0, extra = 0;
          final maxExtra = (oldS.length * 0.15 + 2).floor();
          while (i < oldS.length && j < newS.length) {
            if (oldS[i] == newS[j]) {
              i++;
              j++;
            } else {
              extra++;
              j++;
              if (extra > maxExtra) return false;
            }
          }
          return i == oldS.length; // cubrimos todo oldS
        }

        if (newStr.length >= curStr.length && fuzzySuperset(curStr, newStr)) {
          _currentAiResponseText = seg;
        } else {
          // 3c. Heurística adicional: reescritura completa detectada por similitud de tokens temprana (evitar duplicar saludo + contenido re-escrito)
          // Caso típico: "Hola mi amor estoy pensando en ti" seguido por "¡Hola, mi amor! ¡Qué alegría escucharte..." -> reemplazar.
          List<String> tokenize(String s) {
            final lower = s.toLowerCase();
            final replaced = lower
                .replaceAll('á', 'a')
                .replaceAll('é', 'e')
                .replaceAll('í', 'i')
                .replaceAll('ó', 'o')
                .replaceAll('ú', 'u')
                .replaceAll('ü', 'u')
                .replaceAll('ñ', 'n')
                .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
            return replaced.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
          }

          bool probableRewrite(String oldText, String newText) {
            if (newText.length < oldText.length * 1.1) return false; // debe ser claramente más largo
            if (oldText.length > 140) return false; // evitar reemplazar textos largos (mitigar riesgo)
            final oldTokens = tokenize(oldText);
            if (oldTokens.length < 3) return false; // textos muy cortos ya cubiertos por otras heurísticas
            final newTokens = tokenize(newText);
            // subsecuencia LCS sencilla
            int i = 0, j = 0, matched = 0, lastMatchNewIdx = -1;
            while (i < oldTokens.length && j < newTokens.length) {
              if (oldTokens[i] == newTokens[j]) {
                matched++;
                i++;
                lastMatchNewIdx = j;
                j++;
              } else {
                j++;
              }
            }
            final coverage = matched / oldTokens.length;
            if (coverage < 0.6) return false; // debe cubrir la mayoría de tokens antiguos
            if (lastMatchNewIdx > (oldTokens.length * 2.2)) {
              return false; // coincidencias demasiado tardías (sería una continuación, no reescritura)
            }
            // Prefijo compartido corto indica re-formulación de inicio (no simple continuación)
            int prefixTokenMatches = 0;
            final limit = oldTokens.length < newTokens.length ? oldTokens.length : newTokens.length;
            for (int k = 0; k < limit; k++) {
              if (oldTokens[k] == newTokens[k]) {
                prefixTokenMatches++;
              } else {
                break;
              }
            }
            // Evitar colisionar con el caso de simple continuación (prefijo largo)
            final prefixRatio = prefixTokenMatches / oldTokens.length;
            if (prefixRatio >= 0.85) return false; // es muy parecido al inicio (continuación probable)
            // Si contiene saludos al principio reforzar probabilidad
            final hasGreeting = newTokens
                .take(4)
                .any((t) => ['hola', 'buenos', 'buen', 'buenas', 'hey', 'oye'].contains(t));
            return hasGreeting || coverage >= 0.75;
          }

          if (probableRewrite(current, seg)) {
            if (_subtitleDebug) {
              debugPrint('🔁 [SUB-BUF] Detectada reescritura completa -> reemplazo');
            }
            _currentAiResponseText = seg;
          } else {
            // 4. Intentar fusión por solapamiento sufijo/prefijo
            int overlap = 0;
            final maxCheck = current.length < seg.length ? current.length : seg.length;
            for (int i = maxCheck; i >= 8; i--) {
              // mínimo 8 chars para considerar
              if (current.endsWith(seg.substring(0, i))) {
                overlap = i;
                break;
              }
            }
            if (overlap > 0) {
              _currentAiResponseText = current + seg.substring(overlap);
            } else if (seg.startsWith(current)) {
              _currentAiResponseText = seg; // caso degenerate ya cubierto pero por robustez
            } else {
              // 5. Prefijo común largo (>=60% del actual) => tratar como reemplazo (corrección interna)
              int prefixLen = 0;
              final limit = current.length < seg.length ? current.length : seg.length;
              while (prefixLen < limit && current[prefixLen] == seg[prefixLen]) {
                prefixLen++;
              }
              if (prefixLen >= (current.length * 0.6)) {
                _currentAiResponseText = seg;
              } else {
                // 6. Contenido realmente nuevo: anexar con espacio si procede
                final lastChar = current.isEmpty ? '' : current[current.length - 1];
                final needsSpace =
                    current.isNotEmpty &&
                    !RegExp(r'[\s.,;:!?¡¿]').hasMatch(lastChar) &&
                    !seg.startsWith(RegExp(r'[\s.,;:!?¡¿]'));
                _currentAiResponseText = current + (needsSpace ? ' ' : '') + seg;
              }
            }
          }
        }
      }
    }
    _pendingAiTextSegments
      ..clear()
      ..add(_currentAiResponseText);

    // Post-proceso: eliminar duplicaciones consecutivas largas (a veces el modelo re-emite saludo + versión corregida completa)
    String collapseRepeats(String input) {
      // Dividir por delimitadores fuertes manteniéndolos.
      final regex = RegExp(r'(?<=[.!?¡¿])\s+');
      final parts = input.split(regex).where((p) => p.trim().isNotEmpty).toList();
      if (parts.length < 2) return input;
      String normPart(String p) =>
          p.toLowerCase().replaceAll(RegExp(r'["“”¡!¿?.,;:()\-]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final out = <String>[];
      String? prevNorm;
      for (final raw in parts) {
        final n = normPart(raw);
        if (prevNorm != null) {
          // Duplicado exacto o el nuevo contiene totalmente al anterior
          if (n == prevNorm || n.startsWith(prevNorm) || prevNorm.startsWith(n)) {
            // si el nuevo es más largo (corrección / versión expandida) reemplazar la última
            if (out.isNotEmpty && n.length > prevNorm.length) {
              out[out.length - 1] = raw.trim();
              prevNorm = n;
            }
            continue; // omitir duplicado corto
          }
        }
        out.add(raw.trim());
        prevNorm = n;
      }
      final rebuilt = out.join('. ');
      // Evitar añadir punto extra si ya termina en puntuación
      return rebuilt;
    }

    final collapsed = collapseRepeats(_currentAiResponseText);
    if (collapsed != _currentAiResponseText) {
      _currentAiResponseText = collapsed;
      _pendingAiTextSegments
        ..clear()
        ..add(_currentAiResponseText);
      if (_subtitleDebug) {
        debugPrint('♻️  [SUB-BUF] Post-colapso duplicados');
      }
    }

    // Segunda pasada: detectar repeticiones consecutivas de la MISMA secuencia de tokens dentro de una única frase
    // Ej: "Hola mi amor estoy pensando en ti hola mi amor estoy pensando en ti" -> mantener solo una.
    String collapseInternalLoops(String input) {
      // Trabajamos a nivel de tokens separados por espacio para no romper puntuación adosada (",", "." etc.).
      final tokens = input.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length < 8) return input; // muy corto, improbable loop largo
      final keep = List<bool>.filled(tokens.length, true);
      int i = 0;
      while (i < tokens.length) {
        // Longitud máxima de ventana a probar: mitad restante
        final maxLen = ((tokens.length - i) / 2).floor();
        bool removedAny = false;
        for (int len = maxLen; len >= 3; len--) {
          // secuencias mínimas de 3 tokens
          if (i + 2 * len > tokens.length) continue;
          bool equal = true;
          for (int k = 0; k < len; k++) {
            final a = tokens[i + k];
            final b = tokens[i + len + k];
            if (a.toLowerCase() != b.toLowerCase()) {
              equal = false;
              break;
            }
          }
          if (!equal) continue;
          // Verificar que la secuencia tiene peso informativo (>=12 chars alfanuméricas)
          final seq = tokens.sublist(i, i + len).join(' ');
          final alnumLen = seq.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]'), '').length;
          if (alnumLen < 12) continue; // evitar colapsar repeticiones cortas estilísticas
          // Marcar repeticiones consecutivas adicionales (puede haber más de 2)
          int repeatStart = i + len;
          while (repeatStart + len <= tokens.length) {
            bool again = true;
            for (int k = 0; k < len; k++) {
              if (tokens[i + k].toLowerCase() != tokens[repeatStart + k].toLowerCase()) {
                again = false;
                break;
              }
            }
            if (!again) break;
            for (int k = repeatStart; k < repeatStart + len; k++) {
              keep[k] = false; // eliminar repetición
            }
            repeatStart += len;
            removedAny = true;
          }
          if (removedAny) break; // dejamos la primera ocurrencia (más larga válida)
        }
        i++;
      }
      if (!keep.contains(false)) return input; // nada colapsado
      final rebuilt = <String>[];
      for (int t = 0; t < tokens.length; t++) {
        if (keep[t]) rebuilt.add(tokens[t]);
      }
      // Reconstruir con un solo espacio; luego limpiar espacios antes de puntuación.
      String out = rebuilt.join(' ');
      // Quitar espacios antes de signos de puntuación manteniendo el signo (usar replaceAllMapped para evitar literales "$1")
      out = out.replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m.group(1)!);
      return out;
    }

    final collapsed2 = collapseInternalLoops(_currentAiResponseText);
    if (collapsed2 != _currentAiResponseText) {
      _currentAiResponseText = collapsed2;
      _pendingAiTextSegments
        ..clear()
        ..add(_currentAiResponseText);
      if (_subtitleDebug) {
        debugPrint('🧿 [SUB-BUF] Colapsadas repeticiones intra-frase');
      }
    }
    if (_subtitleDebug) {
      debugPrint('🧵 [SUB-BUF] Consolidado len=${_currentAiResponseText.length}');
    }
    // Asignación directa de delta textual al último chunk de audio
    final newLen = _currentAiResponseText.length;
    if (newLen > prevLenBeforeMerge) {
      final delta = _currentAiResponseText.substring(prevLenBeforeMerge, newLen);
      if (_audioChunkMetas.isEmpty) {
        (_preAudioTextBuffer ??= StringBuffer()).write(delta); // todavía no hay audio
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
    out = out.replaceAllMapped(RegExp(r'([^\.])\.{2}(?!\.)'), (m) => '${m.group(1)}.'); // dos puntos -> uno
    out = out.replaceAllMapped(RegExp(r'([\.\!\?])\s*\.'), (m) => m.group(1)!); // "?." -> "?"
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
    RegExp(r'Subt[ií]tulos por la comunidad de Amara', caseSensitive: false),
    RegExp(r'^¿?Viemos\??$', caseSensitive: false),
  ];
  String? _filterUserTranscript(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    for (final p in _bannedTranscriptPatterns) {
      if (p.hasMatch(t)) return null;
    }
    if (t.length <= 2 && !RegExp(r'[aeiouáéíóú]').hasMatch(t.toLowerCase())) return null;
    return t;
  }

  void _emitFullSubtitleIfPending() {
    if (_uiOnText != null && _fullAiText.isNotEmpty) {
      _uiOnText!(_fullAiText);
    } else if (_uiOnText != null && _pendingAiTextSegments.isNotEmpty) {
      _uiOnText!(_pendingAiTextSegments.join(''));
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
    final file = File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(data);
    return file;
  }

  void dispose() {
    _stopMicrophoneCapture();
    _audioPlayer.dispose();
    _ringPlayer.dispose();
    _recorder?.dispose();
    _micLevelController.close();
    _playbackTimer?.cancel();
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
