import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/voice/infrastructure/audio/audio_playback.dart';
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../voice/infrastructure/adapters/google_speech_service.dart';
import '../../../voice/infrastructure/adapters/android_native_tts_service.dart';
import 'package:ai_chan/core/cache/cache_service.dart';
import 'package:ai_chan/core/models.dart';
import '../../domain/interfaces/i_audio_chat_service.dart';

/// Servicio que encapsula grabación, transcripción parcial, reproducción y TTS.
class AudioChatService implements IAudioChatService {
  final AudioRecorder _recorder = AudioRecorder();
  @override
  bool isRecording = false;
  bool _recordCancelled = false;
  DateTime? _recordStart;
  String? _currentRecordingPath;
  StreamSubscription<Amplitude>? _ampSub;
  final List<int> _currentWaveform = [];
  @override
  List<int> get currentWaveform => List.unmodifiable(_currentWaveform);
  String _liveTranscript = '';
  @override
  String get liveTranscript => _liveTranscript;
  @override
  Duration get recordingElapsed => _recordStart == null ? Duration.zero : DateTime.now().difference(_recordStart!);

  Timer? _partialTxTimer;
  bool _isPartialTranscribing = false;

  final AudioPlayback _audioPlayer = di.getAudioPlayback();
  String? _currentPlayingId;
  @override
  bool isPlayingMessage(Message m) => _currentPlayingId == m.audioPath;
  // Tracking posición/duración para subtítulos flotantes
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  @override
  Duration get currentPosition => _currentPosition;
  @override
  Duration get currentDuration => _currentDuration;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  final OnStateChanged onStateChanged;
  final OnWaveformUpdate onWaveform;

  AudioChatService({required this.onStateChanged, required this.onWaveform});

  @override
  Future<void> startRecording() async {
    if (isRecording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('[Audio] Permiso micrófono denegado');
      return;
    }
    // Record directly into the configured local audio directory so we avoid
    // cross-filesystem rename issues (writing into /tmp then moving to
    // AUDIO_DIR can fail with EXDEV). The filename uses the start timestamp
    // so it stays stable for logs and later correlation.
    final localDir = await audio_utils.getLocalAudioDir();
    final path = '${localDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  @override
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
      // Since we now record directly into the persistent audio dir, if the
      // returned path is already inside that dir we can short-circuit and
      // return it without renaming/copying. This avoids EXDEV errors and
      // preserves atomicity when the recorder already wrote into the same
      // filesystem.
      String result = path;
      try {
        final dir = await audio_utils.getLocalAudioDir();
        if (path.startsWith(dir.path)) {
          debugPrint('[Audio] stopRecording: recording already in audio dir: $path');
          result = path;
        } else {
          // Fallback: try to move into audio dir (rare, kept for safety)
          final ts = _recordStart?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
          final dest = '${dir.path}/voice_$ts.m4a';
          final f = File(path);
          if (await f.exists()) {
            try {
              await f.rename(dest);
              final newLen = await File(dest).length();
              debugPrint('[Audio] stopRecording moved file to $dest (size=$newLen bytes)');
              result = dest;
            } catch (e) {
              debugPrint('[Audio] stopRecording rename failed: $e; falling back to copy');
              try {
                await f.copy(dest);
                final newLen = await File(dest).length();
                debugPrint('[Audio] stopRecording copied file to $dest (size=$newLen bytes)');
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

  @override
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

  @override
  Future<void> togglePlay(Message msg, OnStateChanged onState) async {
    if (!msg.isAudio || msg.audioPath == null) return;
    debugPrint('[Audio] togglePlay called, audioPath=${msg.audioPath}');
    try {
      final fcheck = File(msg.audioPath!);
      debugPrint(
        '[Audio] togglePlay file exists=${fcheck.existsSync()}, size=${fcheck.existsSync() ? fcheck.lengthSync() : 0}',
      );
    } catch (_) {}
    // If the audio file does not actually exist, fail fast and let the caller
    // (ChatProvider) handle the error and show a SnackBar. This avoids
    // invoking platform audio APIs with non-existent paths which can emit
    // uncaught PlatformExceptions from the plugin.
    try {
      final path = msg.audioPath;
      if (path == null) return;
      final f = File(path);
      if (!await f.exists()) {
        debugPrint('[Audio] togglePlay aborting - file not found: $path');
        throw Exception('Audio file not found: $path');
      }
    } catch (e) {
      // Rethrow so the provider can catch and show a user-friendly message.
      rethrow;
    }
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
      await _audioPlayer.play(msg.audioPath!);
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

  @override
  /// If `forDialogDemo` is true, the service will prefer cached audio (used
  /// by `tts_configuration_dialog` demos). For normal message TTS, files are
  /// persisted to the configured `AUDIO_DIR_*` directory. For calls, caller
  /// should use temporary-only output.
  Future<File?> synthesizeTts(
    String text, {
    String voice = 'sage',
    String? languageCode,
    bool forDialogDemo = false,
  }) async {
    debugPrint('[Audio][TTS] synthesizeTts called - voice: $voice, languageCode: $languageCode');

    // Prepare the actual text that will be sent to the TTS providers.
    // - For assistant message TTS (not dialog demos), if the text is wrapped
    //   in paired [audio]...[/audio] tags we should synthesize only the
    //   inner content (strip the tags). This preserves tags for storage/UI
    //   but avoids reading them aloud.
    // - Also, control tags used for calls ([start_call], [end_call]) must
    //   never be synthesized. If after removing those tags there is no
    //   remaining printable text, skip TTS and return null.
    String synthText = text;
    try {
      if (!forDialogDemo) {
        // Strip paired [audio]...[/audio] and use inner content when present
        final openTag = '[audio]';
        final closeTag = '[/audio]';
        final low = text.toLowerCase();
        final start = low.indexOf(openTag);
        if (start != -1) {
          final after = text.substring(start + openTag.length);
          final lowerAfter = after.toLowerCase();
          final end = lowerAfter.indexOf(closeTag);
          if (end != -1) {
            final inner = after.substring(0, end).trim();
            if (inner.isNotEmpty) {
              synthText = inner;
              debugPrint('[Audio][TTS] Stripped [audio] tags for synthesis, len=${synthText.length}');
            }
          }
        }

        // Remove any call control tags and if nothing remains, skip TTS.
        try {
          final withoutCalls = synthText
              .replaceAll(RegExp(r'\[\/?start_call\]', caseSensitive: false), '')
              .replaceAll(RegExp(r'\[\/?end_call\]', caseSensitive: false), '')
              .trim();
          if (withoutCalls.isEmpty) {
            debugPrint('[Audio][TTS] Message contains only call control tags; skipping synthesis');
            return null;
          }
        } catch (_) {}
      }
    } catch (_) {}

    try {
      // Determinar provider activo: prefs -> env (compatibilidad gemini->google).
      // Si el usuario configuró explícitamente el provider (p.ej. 'google' o 'openai'), lo respetamos.
      // Solo haremos auto-detección por nombre de voz si la preferencia es 'auto' o no está configurada.
      String provider = 'google';
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('selected_audio_provider');
        if (saved != null) {
          provider = (saved == 'gemini') ? 'google' : saved.toLowerCase();
          debugPrint('[Audio][TTS] Provider selected from prefs: $provider');
        } else {
          final env = Config.getAudioProvider().toLowerCase();
          if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
        }
      } catch (_) {
        final env = Config.getAudioProvider().toLowerCase();
        if (env.isNotEmpty) provider = (env == 'gemini') ? 'google' : env;
      }

      // Si la preferencia pide detección automática o no se especificó, detectar por voz.
      if (provider == 'auto' || provider.isEmpty) {
        const openAIVoices = ['sage', 'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
        if (openAIVoices.contains(voice)) {
          provider = 'openai';
          debugPrint('[Audio][TTS] Auto-detected OpenAI voice: $voice, using OpenAI provider');
        } else {
          provider = 'google';
        }
      }

      debugPrint('[Audio][TTS] Using provider: $provider for voice: $voice');

      // Probar TTS nativo de Android primero si está disponible - PERO SOLO para voces que no son de OpenAI ni Google Cloud
      if (provider != 'openai' && provider != 'google' && AndroidNativeTtsService.isAndroid) {
        debugPrint('[Audio][TTS] Trying Android native TTS for non-OpenAI/non-Google voice: $voice');
        final isNativeAvailable = await AndroidNativeTtsService.isNativeTtsAvailable();
        if (isNativeAvailable) {
          // Buscar caché primero
          final cachedFile = await CacheService.getCachedAudioFile(
            text: text,
            voice: voice,
            languageCode: languageCode ?? 'es-ES',
            provider: 'android_native',
            extension: 'mp3',
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
              text: synthText,
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
                    extension: 'mp3',
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
      } else if (provider == 'openai') {
        debugPrint('[Audio][TTS] Skipping Android native TTS for OpenAI voice: $voice');
      } else if (provider == 'google') {
        debugPrint('[Audio][TTS] Skipping Android native TTS for Google Cloud voice: $voice');
      }

      if (provider == 'google') {
        // voice is expected to be a Google voice name like 'es-ES-Wavenet-F'
        // If caller passed an OpenAI voice name or empty string, map to
        // configured Google default so the cache lookup uses the Google
        // voice name (avoids regenerating audio that was cached under the
        // Google voice name).
        var voiceToUse = voice;
        const openAIVoices = ['sage', 'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
        if (voiceToUse.trim().isEmpty || openAIVoices.contains(voiceToUse)) {
          final googleDefault = Config.getGoogleVoice();
          if (googleDefault.isNotEmpty) {
            debugPrint('[Audio][TTS] Mapping voice "$voice" -> Google default voice: $googleDefault');
            voiceToUse = googleDefault;
          }
        }

        if (GoogleSpeechService.isConfigured) {
          try {
            final lang = languageCode ?? 'es-ES';
            final file = await GoogleSpeechService.textToSpeechFile(
              text: synthText,
              voiceName: voiceToUse,
              languageCode: lang,
              useCache: forDialogDemo,
            );
            if (file != null) {
              debugPrint('[Audio][TTS] Google TTS success');

              // If this is a regular message (not a dialog demo), persist
              // the file into the configured local audio directory so the
              // user can access it later instead of leaving it in /tmp.
              if (!forDialogDemo) {
                try {
                  final localDir = await audio_utils.getLocalAudioDir();
                  final oldFile = file;
                  final fileName = oldFile.path.split('/').last;
                  final destPath = '${localDir.path}/$fileName';

                  try {
                    await oldFile.rename(destPath);
                    debugPrint('[Audio][TTS] Moved Google TTS file to $destPath');
                    return File(destPath);
                  } catch (e) {
                    debugPrint('[Audio][TTS] rename failed: $e; trying copy');
                    try {
                      await oldFile.copy(destPath);
                      // Verify sizes before removing original
                      try {
                        final srcLen = await oldFile.length();
                        final dstLen = await File(destPath).length();
                        if (srcLen == dstLen) {
                          try {
                            await oldFile.delete();
                          } catch (_) {}
                        } else {
                          debugPrint('[Audio][TTS] copy size mismatch src=$srcLen dst=$dstLen; keeping original');
                        }
                      } catch (e2) {
                        debugPrint('[Audio][TTS] verify error after copy: $e2');
                      }
                      return File(destPath);
                    } catch (e2) {
                      debugPrint('[Audio][TTS] copy failed: $e2; returning original file');
                      return oldFile;
                    }
                  }
                } catch (e) {
                  debugPrint('[Audio][TTS] Error moving Google TTS file to audio dir: $e; returning original file');
                  return file;
                }
              }

              return file;
            }
            debugPrint('[Audio][TTS] Google TTS returned null file, falling back to DI service');
          } catch (e) {
            debugPrint('[Audio][TTS] Google TTS error: $e — falling back to DI service');
          }
        } else {
          debugPrint('[Audio][TTS] Google TTS not configured (no API key) — falling back to DI service');
        }
      } else if (provider == 'openai') {
        // Para voces de OpenAI, usar directamente el OpenAI adapter
        debugPrint('[Audio][TTS] Using OpenAI adapter for voice: $voice');
        try {
          // Usar el adapter de OpenAI que ya está configurado
          final aiService = di.getAIServiceForModel('gpt-4o-mini'); // Usar un modelo GPT para forzar OpenAI
          final filePath = await aiService.textToSpeech(synthText, voice: voice);
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) {
              debugPrint('[Audio][TTS] OpenAI TTS success: $filePath');
              return file;
            }
          }
          debugPrint('[Audio][TTS] OpenAI adapter returned null, falling back to DI service');
        } catch (e) {
          debugPrint('[Audio][TTS] OpenAI adapter error: $e — falling back to DI service');
        }
      }

      // Fallback / default: delegate to the configured ITtsService (registered in DI)
      try {
        // For regular message TTS, prefer saving under the configured audio dir
        // so the user can access sent/received audios. For dialog demos, the
        // TTS services may return cached files.
        if (!forDialogDemo) {
          final tts = di.getTtsService();
          final path = await tts.synthesizeToFile(
            text: synthText,
            options: {
              'voice': voice,
              'languageCode': languageCode ?? 'es-ES',
              'outputDir': (await audio_utils.getLocalAudioDir()).path,
            },
          );
          if (path == null) return null;
          final f = File(path);
          if (await f.exists()) return f;
          return null;
        } else {
          final tts = di.getTtsService();
          final path = await tts.synthesizeToFile(
            text: synthText,
            options: {'voice': voice, 'languageCode': languageCode ?? 'es-ES'},
          );
          if (path == null) return null;
          final f = File(path);
          if (await f.exists()) return f;
          return null;
        }
      } catch (e) {
        debugPrint('[Audio][TTS] DI fallback error: $e');
        return null;
      }
    } catch (e) {
      debugPrint('[Audio][TTS] Error: $e');
      return null;
    }
  }

  @override
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
