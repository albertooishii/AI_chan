import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/audio_utils.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_speech_service.dart';
import 'android_native_tts_service.dart';
import '../core/cache/cache_service.dart';
import 'package:ai_chan/core/models.dart';

typedef OnStateChanged = void Function();
typedef OnWaveformUpdate = void Function(List<int> waveform);

/// Servicio que encapsula grabación, transcripción parcial, reproducción y TTS.
class AudioChatService {
  final AudioRecorder _recorder = AudioRecorder();
  bool isRecording = false;
  bool _recordCancelled = false;
  DateTime? _recordStart;
  String? _currentRecordingPath;
  StreamSubscription<Amplitude>? _ampSub;
  final List<int> _currentWaveform = [];
  List<int> get currentWaveform => List.unmodifiable(_currentWaveform);
  String _liveTranscript = '';
  String get liveTranscript => _liveTranscript;
  Duration get recordingElapsed => _recordStart == null ? Duration.zero : DateTime.now().difference(_recordStart!);

  Timer? _partialTxTimer;
  bool _isPartialTranscribing = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentPlayingId;
  bool isPlayingMessage(Message m) => _currentPlayingId == m.audioPath;
  // Tracking posición/duración para subtítulos flotantes
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  Duration get currentPosition => _currentPosition;
  Duration get currentDuration => _currentDuration;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  final OnStateChanged onStateChanged;
  final OnWaveformUpdate onWaveform;

  AudioChatService({required this.onStateChanged, required this.onWaveform});

  Future<void> startRecording() async {
    if (isRecording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('[Audio] Permiso micrófono denegado');
      return;
    }
    final dir = await getLocalAudioDir();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000), path: path);
    isRecording = true;
    _recordCancelled = false;
    _currentWaveform.clear();
    _recordStart = DateTime.now();
    _currentRecordingPath = path;
    _liveTranscript = '';
    _startPartialLoop();
    try {
      await _ampSub?.cancel();
      _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amp) {
        final value = amp.current;
        double norm = (value + 45) / 45;
        norm = norm.clamp(0, 1);
        _currentWaveform.add((norm * 100).round());
        if (_currentWaveform.length > 160) _currentWaveform.removeAt(0);
        onWaveform(List.unmodifiable(_currentWaveform));
        onStateChanged();
      });
    } catch (_) {}
    onStateChanged();
  }

  Future<String?> stopRecording({bool cancelled = false}) async {
    if (!isRecording) return null;
    try {
      final path = await _recorder.stop();
      isRecording = false;
      await _ampSub?.cancel();
      _stopPartialLoop();
      if (path == null) return null;
      if (cancelled || _recordCancelled) {
        try {
          File(path).deleteSync();
        } catch (_) {}
        _liveTranscript = '';
        _currentRecordingPath = null;
        onStateChanged();
        return null;
      }
      // Copiar a directorio local persistente para evitar que el archivo temporal sea eliminado
      String result = path;
      try {
        final dir = await getLocalAudioDir();
        final dest = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final f = File(path);
        if (await f.exists()) {
          // Intentar mover (rename) primero — es atómico si está en el mismo filesystem
          try {
            await f.rename(dest);
            debugPrint('[Audio] stopRecording moved file to $dest');
            result = dest;
          } catch (e) {
            // Si falla (p.ej. distinto filesystem), caer a copy+verify+delete
            debugPrint('[Audio] stopRecording rename failed: $e; falling back to copy');
            try {
              await f.copy(dest);
              debugPrint('[Audio] stopRecording copied file to $dest');
              // Verificar tamaños antes de eliminar el original
              try {
                final srcLen = await f.length();
                final dstLen = await File(dest).length();
                if (srcLen == dstLen) {
                  try {
                    await f.delete();
                    debugPrint('[Audio] stopRecording deleted original file $path after verify');
                  } catch (_) {}
                } else {
                  debugPrint('[Audio] stopRecording copy size mismatch src=$srcLen dst=$dstLen; keeping original');
                }
              } catch (e2) {
                debugPrint('[Audio] stopRecording verify error: $e2');
              }
              result = dest;
            } catch (e2) {
              debugPrint('[Audio] stopRecording copy error: $e2');
            }
          }
        } else {
          debugPrint('[Audio] stopRecording: original file not found for copy: $path');
        }
      } catch (e) {
        debugPrint('[Audio] stopRecording copy error: $e');
      }
      _currentRecordingPath = null;
      onStateChanged();
      return result;
    } catch (e) {
      debugPrint('[Audio] Error al detener: $e');
      isRecording = false;
      await _ampSub?.cancel();
      _stopPartialLoop();
      onStateChanged();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _recordCancelled = true;
    await stopRecording(cancelled: true);
  }

  void _startPartialLoop() {
    _partialTxTimer?.cancel();
    _partialTxTimer = Timer.periodic(const Duration(seconds: 4), (_) => _attemptPartial());
  }

  void _stopPartialLoop() {
    _partialTxTimer?.cancel();
    _partialTxTimer = null;
    _isPartialTranscribing = false;
  }

  Future<void> _attemptPartial() async {
    if (!isRecording) return;
    if (_isPartialTranscribing) return;
    final path = _currentRecordingPath;
    if (path == null) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      int len;
      try {
        len = await file.length();
      } catch (e) {
        debugPrint('[Audio] Parcial length error: $e');
        return;
      }
      if (len < 24000) return;
      _isPartialTranscribing = true;
      final stt = di.getSttService();
      final partial = await stt.transcribeAudio(path);
      if (partial != null && partial.trim().isNotEmpty) {
        if (partial.trim().length > _liveTranscript.trim().length) {
          _liveTranscript = partial.trim();
          onStateChanged();
        }
      }
    } catch (e) {
      debugPrint('[Audio] Parcial error: $e');
    } finally {
      _isPartialTranscribing = false;
    }
  }

  Future<void> togglePlay(Message msg, OnStateChanged onState) async {
    if (!msg.isAudio || msg.audioPath == null) return;
    debugPrint('[Audio] togglePlay called, audioPath=${msg.audioPath}');
    try {
      final fcheck = File(msg.audioPath!);
      debugPrint(
        '[Audio] togglePlay file exists=${fcheck.existsSync()}, size=${fcheck.existsSync() ? fcheck.lengthSync() : 0}',
      );
    } catch (_) {}
    if (_currentPlayingId == msg.audioPath) {
      await _audioPlayer.stop();
      _currentPlayingId = null;
      _currentPosition = Duration.zero;
      _currentDuration = Duration.zero;
      await _posSub?.cancel();
      await _durSub?.cancel();
      onState();
      return;
    }
    try {
      await _audioPlayer.stop();
      _currentPlayingId = msg.audioPath;
      _currentPosition = Duration.zero;
      _currentDuration = Duration.zero;
      await _posSub?.cancel();
      await _durSub?.cancel();
      await _audioPlayer.play(DeviceFileSource(msg.audioPath!));
      _durSub = _audioPlayer.onDurationChanged.listen((d) {
        _currentDuration = d;
        onState();
      });
      _posSub = _audioPlayer.onPositionChanged.listen((p) {
        _currentPosition = p;
        onState();
      });
      _audioPlayer.onPlayerComplete.listen((event) async {
        _currentPlayingId = null;
        _currentPosition = _currentDuration;
        try {
          await _posSub?.cancel();
        } catch (_) {}
        try {
          await _durSub?.cancel();
        } catch (_) {}
        onState();
      });
      onState();
    } catch (e) {
      debugPrint('[Audio] Play error: $e');
      _currentPlayingId = null;
      _currentPosition = Duration.zero;
      _currentDuration = Duration.zero;
      await _posSub?.cancel();
      await _durSub?.cancel();
      onState();
    }
  }

  Future<File?> synthesizeTts(String text, {String voice = 'sage', String? languageCode}) async {
    try {
      // Determinar provider activo: prefs -> env (compatibilidad gemini->google)
      String provider = 'google';
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('selected_audio_provider');
        if (saved != null) {
          provider = (saved == 'gemini') ? 'google' : saved.toLowerCase();
        } else {
          final env = Config.getAudioProvider().toLowerCase();
          if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
        }
      } catch (_) {
        final env = Config.getAudioProvider().toLowerCase();
        if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
      }

      // Probar TTS nativo de Android primero si está disponible
      if (AndroidNativeTtsService.isAndroid) {
        final isNativeAvailable = await AndroidNativeTtsService.isNativeTtsAvailable();
        if (isNativeAvailable) {
          // Buscar caché primero
          final cachedFile = await CacheService.getCachedAudioFile(
            text: text,
            voice: voice,
            languageCode: languageCode ?? 'es-ES',
            provider: 'android_native',
          );

          if (cachedFile != null) {
            debugPrint('[Audio][TTS] Usando audio nativo Android desde caché');
            return cachedFile;
          }

          // Generar con TTS nativo si no está en caché
          try {
            final cacheDir = await CacheService.getAudioCacheDirectory();
            final outputPath = '${cacheDir.path}/android_native_${DateTime.now().millisecondsSinceEpoch}.mp3';

            final result = await AndroidNativeTtsService.synthesizeToFile(
              text: text,
              outputPath: outputPath,
              voiceName: voice,
              languageCode: languageCode ?? 'es-ES',
            );

            if (result != null) {
              final file = File(result);
              if (await file.exists()) {
                debugPrint('[Audio][TTS] Audio generado con TTS nativo Android');

                // Guardar referencia en caché
                try {
                  final audioData = await file.readAsBytes();
                  await CacheService.saveAudioToCache(
                    audioData: audioData,
                    text: text,
                    voice: voice,
                    languageCode: languageCode ?? 'es-ES',
                    provider: 'android_native',
                  );
                } catch (e) {
                  debugPrint('[Audio][TTS] Warning: Error guardando TTS nativo en caché: $e');
                }

                return file;
              }
            }
          } catch (e) {
            debugPrint('[Audio][TTS] Error con TTS nativo Android, continuando con $provider: $e');
          }
        }
      }

      if (provider == 'google') {
        // voice is expected to be a Google voice name like 'es-ES-Neural2-A'
        if (GoogleSpeechService.isConfigured) {
          try {
            final lang = languageCode ?? 'es-ES';
            final file = await GoogleSpeechService.textToSpeechFile(text: text, voiceName: voice, languageCode: lang);
            if (file != null) return file;
            debugPrint('[Audio][TTS] Google TTS returned null file, falling back to OpenAI');
          } catch (e) {
            debugPrint('[Audio][TTS] Google TTS error: $e — falling back to OpenAI');
          }
        } else {
          debugPrint('[Audio][TTS] Google TTS not configured (no API key) — falling back to OpenAI');
        }
      }

      // Fallback / default: delegate to the configured ITtsService (registered in DI)
      try {
        final tts = di.getTtsService();
        final path = await tts.synthesizeToFile(
          text: text,
          options: {'voice': voice, 'languageCode': languageCode ?? 'es-ES'},
        );
        if (path == null) return null;
        final f = File(path);
        if (await f.exists()) return f;
        return null;
      } catch (e) {
        debugPrint('[Audio][TTS] DI fallback error: $e');
        return null;
      }
    } catch (e) {
      debugPrint('[Audio][TTS] Error: $e');
      return null;
    }
  }

  void dispose() {
    _partialTxTimer?.cancel();
    _ampSub?.cancel();
    try {
      _posSub?.cancel();
    } catch (_) {}
    try {
      _durSub?.cancel();
    } catch (_) {}
    _audioPlayer.dispose();
  }
}
