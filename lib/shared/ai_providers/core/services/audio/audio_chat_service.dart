import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:ai_chan/shared.dart' as di;
import 'package:ai_chan/shared.dart' as audio_utils;
import 'package:ai_chan/shared.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';

/// Servicio que encapsula grabación, transcripción parcial, reproducción y TTS.
class AudioChatService implements IAudioChatService {
  AudioChatService({required this.onStateChanged, required this.onWaveform});

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
  Duration get recordingElapsed => _recordStart == null
      ? Duration.zero
      : DateTime.now().difference(_recordStart!);

  Timer? _partialTxTimer;
  bool _isPartialTranscribing = false;
  // Native speech-to-text (live) helper
  stt.SpeechToText? _speech;
  bool _isNativeListening = false;

  final AudioPlayback _audioPlayer = di.getAudioPlayback();
  String? _currentPlayingId;
  @override
  bool isPlayingMessage(final Message m) => _currentPlayingId == m.audio?.url;
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
    final path =
        '${localDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(bitRate: 96000), path: path);
    isRecording = true;
    _recordCancelled = false;
    _currentWaveform.clear();
    _recordStart = DateTime.now();
    _currentRecordingPath = path;
    _liveTranscript = '';
    // Decide whether to use native live STT or file-based partials
    try {
      final provider = await PrefsUtils.getSelectedAudioProvider();
      if (provider == 'native' || provider == 'android_native') {
        // Try to initialize speech_to_text for live partials. If init fails,
        // fall back to the file-based partial loop.
        try {
          _speech = stt.SpeechToText();
          final initialized = await _speech!.initialize(
            onStatus: (final s) {},
            onError: (final e) {},
          );
          if (initialized) {
            _isNativeListening = true;
            _speech!.listen(
              onResult: (final r) {
                try {
                  final text = r.recognizedWords.trim();
                  if (text.isNotEmpty &&
                      text.length > _liveTranscript.trim().length) {
                    _liveTranscript = text;
                    onStateChanged();
                  }
                  // If this result is final, keep it as the authoritative
                  // live transcript (we don't stop listening here to allow
                  // continuous updates; ChatProvider will consume
                  // audioService.liveTranscript as final when native
                  // provider is selected).
                } on Exception catch (_) {}
              },
            );
          } else {
            _speech = null;
            _startPartialLoop();
          }
        } on Exception catch (e) {
          debugPrint(
            '[Audio] native STT init error: $e; falling back to file partials',
          );
          _speech = null;
          _startPartialLoop();
        }
      } else {
        _startPartialLoop();
      }
    } on Exception catch (_) {
      _startPartialLoop();
    }
    try {
      await _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((final amp) {
            final value = amp.current;
            double norm = (value + 45) / 45;
            norm = norm.clamp(0, 1);
            _currentWaveform.add((norm * 100).round());
            if (_currentWaveform.length > 160) _currentWaveform.removeAt(0);
            onWaveform(List.unmodifiable(_currentWaveform));
            onStateChanged();
          });
    } on Exception catch (_) {}
    onStateChanged();
  }

  @override
  Future<String?> stopRecording({final bool cancelled = false}) async {
    if (!isRecording) return null;
    try {
      final path = await _recorder.stop();
      isRecording = false;
      await _ampSub?.cancel();
      // Stop native listening if active
      if (_isNativeListening) {
        try {
          await _speech?.stop();
        } on Exception catch (_) {}
        _isNativeListening = false;
        _speech = null;
      }
      _stopPartialLoop();
      if (path == null) return null;
      if (cancelled || _recordCancelled) {
        try {
          File(path).deleteSync();
        } on Exception catch (_) {}
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
          debugPrint(
            '[Audio] stopRecording: recording already in audio dir: $path',
          );
          result = path;
        } else {
          // Fallback: try to move into audio dir (rare, kept for safety)
          final ts =
              _recordStart?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch;
          final dest = '${dir.path}/voice_$ts.m4a';
          final f = File(path);
          if (f.existsSync()) {
            try {
              await f.rename(dest);
              final newLen = await File(dest).length();
              debugPrint(
                '[Audio] stopRecording moved file to $dest (size=$newLen bytes)',
              );
              result = dest;
            } on Exception catch (e) {
              debugPrint(
                '[Audio] stopRecording rename failed: $e; falling back to copy',
              );
              try {
                await f.copy(dest);
                final newLen = await File(dest).length();
                debugPrint(
                  '[Audio] stopRecording copied file to $dest (size=$newLen bytes)',
                );
                try {
                  final srcLen = await f.length();
                  final dstLen = await File(dest).length();
                  if (srcLen == dstLen) {
                    try {
                      await f.delete();
                      debugPrint(
                        '[Audio] stopRecording deleted original file $path after verify',
                      );
                    } on Exception catch (_) {}
                  } else {
                    debugPrint(
                      '[Audio] stopRecording copy size mismatch src=$srcLen dst=$dstLen; keeping original',
                    );
                  }
                } on Exception catch (e2) {
                  debugPrint('[Audio] stopRecording verify error: $e2');
                }
                result = dest;
              } on Exception catch (e2) {
                debugPrint('[Audio] stopRecording copy error: $e2');
              }
            }
          } else {
            debugPrint(
              '[Audio] stopRecording: original file not found for copy: $path',
            );
          }
        }
      } on Exception catch (e) {
        debugPrint('[Audio] stopRecording copy error: $e');
      }
      _currentRecordingPath = null;
      onStateChanged();
      return result;
    } on Exception catch (e) {
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
    // Ensure native listener is stopped if active
    if (_isNativeListening) {
      try {
        await _speech?.stop();
      } on Exception catch (_) {}
      _isNativeListening = false;
      _speech = null;
    }
    await stopRecording(cancelled: true);
  }

  void _startPartialLoop() {
    _partialTxTimer?.cancel();
    _partialTxTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _attemptPartial(),
    );
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
      if (!file.existsSync()) return;
      int len;
      try {
        len = await file.length();
      } on Exception catch (e) {
        debugPrint('[Audio] Parcial length error: $e');
        return;
      }
      if (len < 24000) return;
      _isPartialTranscribing = true;
      // Respect user-selected audio provider for partial transcription
      final provider = await PrefsUtils.getSelectedAudioProvider();
      final effectiveProvider = provider.isEmpty
          ? AIProviderManager.instance
                    .getProvidersByCapability(AICapability.audioTranscription)
                    .firstOrNull ??
                'unknown'
          : provider;
      final stt = di.getSttServiceForProvider(effectiveProvider);
      final partial = await stt.transcribeAudio(path);
      if (partial != null && partial.trim().isNotEmpty) {
        if (partial.trim().length > _liveTranscript.trim().length) {
          _liveTranscript = partial.trim();
          onStateChanged();
        }
      }
    } on Exception catch (e) {
      debugPrint('[Audio] Parcial error: $e');
    } finally {
      _isPartialTranscribing = false;
    }
  }

  @override
  Future<void> togglePlay(
    final Message msg,
    final OnStateChanged onState,
  ) async {
    if (!msg.isAudio || msg.audio?.url == null) return;
    debugPrint('[Audio] togglePlay called, audioPath=${msg.audio?.url}');
    try {
      final fcheck = File(msg.audio!.url!);
      debugPrint(
        '[Audio] togglePlay file exists=${fcheck.existsSync()}, size=${fcheck.existsSync() ? fcheck.lengthSync() : 0}',
      );
    } on Exception catch (_) {}
    // If the audio file does not actually exist, fail fast and let the caller
    // (ChatProvider) handle the error and show a SnackBar. This avoids
    // invoking platform audio APIs with non-existent paths which can emit
    // uncaught PlatformExceptions from the plugin.
    try {
      final path = msg.audio?.url;
      if (path == null) return;
      final f = File(path);
      if (!f.existsSync()) {
        debugPrint('[Audio] togglePlay aborting - file not found: $path');
        throw Exception('Audio file not found: $path');
      }
    } on Exception {
      // Rethrow so the provider can catch and show a user-friendly message.
      rethrow;
    }
    if (_currentPlayingId == msg.audio?.url) {
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
      _currentPlayingId = msg.audio?.url;
      _currentPosition = Duration.zero;
      _currentDuration = Duration.zero;
      await _posSub?.cancel();
      await _durSub?.cancel();
      await _audioPlayer.play(msg.audio!.url!);
      _durSub = _audioPlayer.onDurationChanged.listen((final d) {
        _currentDuration = d;
        onState();
      });
      _posSub = _audioPlayer.onPositionChanged.listen((final p) {
        _currentPosition = p;
        onState();
      });
      _audioPlayer.onPlayerComplete.listen((final event) async {
        _currentPlayingId = null;
        _currentPosition = _currentDuration;
        try {
          await _posSub?.cancel();
        } on Exception catch (_) {}
        try {
          await _durSub?.cancel();
        } on Exception catch (_) {}
        onState();
      });
      onState();
    } on Exception catch (e) {
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
  Future<String?> synthesizeTts(
    final String text, {
    final String? languageCode,
    final bool forDialogDemo = false,
  }) async {
    debugPrint(
      '[Audio][TTS] synthesizeTts called - languageCode: $languageCode',
    );

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
              debugPrint(
                '[Audio][TTS] Stripped [audio] tags for synthesis, len=${synthText.length}',
              );
            }
          }
        }

        // Remove any call control tags and if nothing remains, skip TTS.
        try {
          final withoutCalls = synthText
              .replaceAll(
                RegExp(r'\[\/?start_call\]', caseSensitive: false),
                '',
              )
              .replaceAll(RegExp(r'\[\/?end_call\]', caseSensitive: false), '')
              .trim();
          if (withoutCalls.isEmpty) {
            debugPrint(
              '[Audio][TTS] Message contains only call control tags; skipping synthesis',
            );
            return null;
          }
        } on Exception catch (_) {}
      }
    } on Exception catch (_) {}

    try {
      // Delegate provider and voice resolution to PrefsUtils
      final provider = await PrefsUtils.getSelectedAudioProvider();
      // Obtener voz preferida dinámicamente del provider configurado
      final preferredVoice = await PrefsUtils.getPreferredVoice();
      debugPrint(
        '[Audio][TTS] Using provider: $provider for voice: $preferredVoice',
      );

      // ✅ DDD: Usar servicio TTS a través de interfaz compartida
      final cloudProviders = AIProviderManager.instance
          .getProvidersByCapability(AICapability.audioGeneration);
      if (!cloudProviders.contains(provider) &&
          await _isAndroidNativeTtsAvailable()) {
        debugPrint(
          '[Audio][TTS] Trying Android native TTS for non-OpenAI/non-Google voice: $preferredVoice',
        );
        final isNativeAvailable = await _checkAndroidNativeTtsAvailable();
        if (isNativeAvailable) {
          // Buscar caché primero
          final cachedFile = await CacheService.getCachedAudioFile(
            text: text,
            voice: preferredVoice,
            languageCode: languageCode ?? 'es-ES',
            provider: 'android_native',
            extension: 'mp3',
          );

          if (cachedFile != null) {
            debugPrint('[Audio][TTS] Usando audio nativo Android desde caché');
            return cachedFile.path;
          }

          // Generar con TTS nativo si no está en caché
          try {
            final cacheDir = await CacheService.getAudioCacheDirectory();
            final outputPath =
                '${cacheDir.path}/android_native_${DateTime.now().millisecondsSinceEpoch}.mp3';

            final result = await _synthesizeAndroidNativeTtsToFile(
              text: synthText,
              outputPath: outputPath,
              voiceName: preferredVoice,
              languageCode: languageCode ?? 'es-ES',
            );

            if (result != null) {
              final file = File(result);
              if (file.existsSync()) {
                debugPrint(
                  '[Audio][TTS] Audio generado con TTS nativo Android',
                );

                // Guardar referencia en caché
                try {
                  final audioData = await file.readAsBytes();
                  await CacheService.saveAudioToCache(
                    audioData: audioData,
                    text: text,
                    voice: preferredVoice,
                    languageCode: languageCode ?? 'es-ES',
                    provider: 'android_native',
                    extension: 'mp3',
                  );
                } on Exception catch (e) {
                  debugPrint(
                    '[Audio][TTS] Warning: Error guardando TTS nativo en caché: $e',
                  );
                }

                return file.path;
              }
            }
          } on Exception catch (e) {
            debugPrint(
              '[Audio][TTS] Error con TTS nativo Android, continuando con $provider: $e',
            );
          }
        }
      } else if (cloudProviders.contains(provider)) {
        debugPrint(
          '[Audio][TTS] Skipping Android native TTS for cloud provider: $provider voice: $preferredVoice',
        );
      }

      // Check for specific providers using provider manager
      final providerInstance = AIProviderManager.instance.providers[provider];
      if (providerInstance?.supportsCapability(AICapability.audioGeneration) ==
          true) {
        // voice is resolved via PrefsUtils.getPreferredVoice to prefer a configured voice for the provider
        final voiceToUse = preferredVoice;

        if (await _isGoogleTtsConfigured()) {
          try {
            final lang = languageCode ?? 'es-ES';
            final file = await _synthesizeGoogleTtsToFile(
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
                  final oldFile = File(file);
                  final fileName = oldFile.path.split('/').last;
                  final destPath = '${localDir.path}/$fileName';

                  try {
                    await oldFile.rename(destPath);
                    debugPrint(
                      '[Audio][TTS] Moved Google TTS file to $destPath',
                    );
                    return destPath;
                  } on Exception catch (e) {
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
                          } on Exception catch (_) {}
                        } else {
                          debugPrint(
                            '[Audio][TTS] copy size mismatch src=$srcLen dst=$dstLen; keeping original',
                          );
                        }
                      } on Exception catch (e2) {
                        debugPrint('[Audio][TTS] verify error after copy: $e2');
                      }
                      return destPath;
                    } on Exception catch (e2) {
                      debugPrint(
                        '[Audio][TTS] copy failed: $e2; returning original file',
                      );
                      return oldFile.path;
                    }
                  }
                } on Exception catch (e) {
                  debugPrint(
                    '[Audio][TTS] Error moving Google TTS file to audio dir: $e; returning original file',
                  );
                  return file;
                }
              }

              return file;
            }
            debugPrint(
              '[Audio][TTS] Google TTS returned null file, falling back to DI service',
            );
          } on Exception catch (e) {
            debugPrint(
              '[Audio][TTS] Google TTS error: $e — falling back to DI service',
            );
          }
        } else {
          debugPrint(
            '[Audio][TTS] Google TTS not configured (no API key) — falling back to DI service',
          );
        }
      } else if (_isKnownTtsProvider(provider)) {
        // 🚀 DINÁMICO: Para proveedores de TTS conocidos, usar sistema dinámico
        debugPrint(
          '[Audio][TTS] Using dynamic provider adapter for voice: $preferredVoice',
        );
        try {
          // Use new Enhanced AI Provider system for TTS
          // Note: TTS via AIProviderManager is not yet implemented
          // Fallback to direct TTS service for now
          debugPrint(
            '[Audio][TTS] Enhanced AI system: TTS not yet implemented, falling back to DI TTS service',
          );

          // Use dedicated TTS service instead of legacy AI service
          final ttsService = di.getTtsServiceForProvider(provider);
          final filePath = await ttsService.synthesizeToFile(text: synthText);
          if (filePath != null) {
            final file = File(filePath);
            if (file.existsSync()) {
              debugPrint('[Audio][TTS] OpenAI TTS success: $filePath');
              return file.path;
            }
          }
          debugPrint(
            '[Audio][TTS] OpenAI adapter returned null, falling back to DI service',
          );
        } on Exception catch (e) {
          debugPrint(
            '[Audio][TTS] OpenAI adapter error: $e — falling back to DI service',
          );
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
              'voice': preferredVoice,
              'languageCode': languageCode ?? 'es-ES',
              'outputDir': (await audio_utils.getLocalAudioDir()).path,
            },
          );
          if (path == null) return null;
          final f = File(path);
          if (f.existsSync()) return f.path;
          return null;
        } else {
          final tts = di.getTtsService();
          final path = await tts.synthesizeToFile(
            text: synthText,
            options: {
              'voice': preferredVoice,
              'languageCode': languageCode ?? 'es-ES',
            },
          );
          if (path == null) return null;
          final f = File(path);
          if (f.existsSync()) return f.path;
          return null;
        }
      } on Exception catch (e) {
        debugPrint('[Audio][TTS] DI fallback error: $e');
        return null;
      }
    } on Exception catch (e) {
      debugPrint('[Audio][TTS] Error: $e');
      return null;
    }
  }

  // ✅ DDD: Métodos auxiliares para encapsular dependencias de otros bounded contexts
  Future<bool> _isAndroidNativeTtsAvailable() async {
    // Encapsular la lógica de Android Native TTS
    try {
      // Usar reflexión o configuración para determinar si está disponible
      // Sin importar directamente AndroidNativeTtsService
      return false; // Temporalmente retornar false para evitar dependencias
    } on Exception {
      return false;
    }
  }

  Future<bool> _checkAndroidNativeTtsAvailable() async {
    // Encapsular la verificación de disponibilidad
    return false; // Temporalmente retornar false
  }

  Future<String?> _synthesizeAndroidNativeTtsToFile({
    required final String text,
    required final String outputPath,
    required final String voiceName,
    required final String languageCode,
  }) async {
    // Encapsular la síntesis TTS nativa de Android
    return null; // Temporalmente retornar null
  }

  Future<bool> _isGoogleTtsConfigured() async {
    // Encapsular la verificación de configuración de Google TTS
    try {
      // Verificar configuración sin importar directamente GoogleSpeechService
      return false; // Temporalmente retornar false
    } on Exception {
      return false;
    }
  }

  Future<String?> _synthesizeGoogleTtsToFile({
    required final String text,
    required final String voiceName,
    required final String languageCode,
    required final bool useCache,
  }) async {
    // Encapsular la síntesis TTS de Google
    return null; // Temporalmente retornar null
  }

  @override
  void dispose() {
    _partialTxTimer?.cancel();
    _ampSub?.cancel();
    if (_isNativeListening) {
      try {
        _speech?.stop();
      } on Exception catch (_) {}
      _isNativeListening = false;
      _speech = null;
    }
    try {
      _posSub?.cancel();
    } on Exception catch (_) {}
    try {
      _durSub?.cancel();
    } on Exception catch (_) {}
    _audioPlayer.dispose();
  }

  /// 🚀 DINÁMICO: Verificar si un proveedor es conocido para TTS
  bool _isKnownTtsProvider(final String provider) {
    // Obtener proveedores con capacidad TTS dinámicamente
    final ttsProviders = AIProviderManager.instance.getProvidersByCapability(
      AICapability.audioGeneration,
    );
    return ttsProviders.contains(provider);
  }
}
