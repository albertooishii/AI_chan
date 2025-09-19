import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ai_chan/shared/ai_providers/core/interfaces/audio/i_audio_playback_service.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/audio_playback_state.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/audio_playback_config.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/audio_playback_result.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/audio_exceptions.dart';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';

/// 🎵 Servicio centralizado para reproducción de audio
/// Usado por TTS, onboarding conversacional y sistema de llamadas
class CentralizedAudioPlaybackService implements IAudioPlaybackService {
  CentralizedAudioPlaybackService._() {
    _setupPlayerListeners();
  }

  static final CentralizedAudioPlaybackService _instance =
      CentralizedAudioPlaybackService._();
  static CentralizedAudioPlaybackService get instance => _instance;

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioPlaybackState> _stateController =
      StreamController<AudioPlaybackState>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completionController =
      StreamController<void>.broadcast();

  AudioPlaybackState _currentState = AudioPlaybackState.idle;
  String? _currentTempFile;
  Duration? _currentAudioDuration;
  AudioPlaybackConfig _currentConfig = AudioPlaybackConfig.defaultConfig;
  bool _isDisposed = false; // ⭐ Nueva bandera para marcar si está dispuesto

  @override
  Stream<AudioPlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;

  @override
  AudioPlaybackState get currentState => _currentState;

  @override
  bool get isPlaying => _currentState == AudioPlaybackState.playing;

  @override
  bool get isPaused => _currentState == AudioPlaybackState.paused;

  @override
  Duration? get currentDuration => _currentAudioDuration;

  void _setupPlayerListeners() {
    _player.onPlayerStateChanged.listen((final PlayerState state) {
      if (_isDisposed) return; // ⭐ No procesar eventos si está dispuesto

      switch (state) {
        case PlayerState.playing:
          _updateState(AudioPlaybackState.playing);
          break;
        case PlayerState.paused:
          _updateState(AudioPlaybackState.paused);
          break;
        case PlayerState.stopped:
          _updateState(AudioPlaybackState.stopped);
          _cleanup();
          break;
        case PlayerState.completed:
          _updateState(AudioPlaybackState.completed);
          // 🎯 Notificar que el audio terminó completamente
          if (_currentConfig.notifyOnCompletion &&
              !_completionController.isClosed) {
            _completionController.add(null);
            Log.d(
              '[CentralizedAudio] 🎵 Audio completado - notificando finalización',
            );
          }
          _cleanup();
          break;
        case PlayerState.disposed:
          _updateState(AudioPlaybackState.idle);
          break;
      }
    });

    // Listener para obtener duración cuando esté disponible
    _player.onDurationChanged.listen((final Duration duration) {
      if (_isDisposed) return; // ⭐ No procesar si está dispuesto

      _currentAudioDuration = duration;
      if (!_durationController.isClosed) {
        _durationController.add(duration);
      }
      Log.d(
        '[CentralizedAudio] 🕐 Duración del audio: ${duration.inMilliseconds}ms',
      );
    });
  }

  void _updateState(final AudioPlaybackState newState) {
    if (_isDisposed) return; // ⭐ No actualizar estado si está dispuesto

    if (_currentState != newState) {
      _currentState = newState;
      // Verificar que el StreamController no esté cerrado antes de agregar eventos
      if (!_stateController.isClosed) {
        _stateController.add(newState);
        Log.d('[CentralizedAudio] Estado: $newState');
      }
    }
  }

  @override
  Future<AudioPlaybackResult> playAudioBytes({
    required final List<int> audioData,
    required final String format,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  }) async {
    if (_isDisposed) {
      Log.w('[CentralizedAudio] ⚠️ Servicio dispuesto, simulando reproducción');
      return AudioPlaybackResult.success(
        duration: Duration(milliseconds: audioData.length ~/ 100),
        metadata: {'simulation': true, 'reason': 'service_disposed'},
      );
    }

    try {
      _currentConfig = config;
      _updateState(AudioPlaybackState.loading);

      // Validar datos de audio
      if (audioData.isEmpty) {
        Log.w(
          '[CentralizedAudio] ⚠️ Datos de audio vacíos, simulando reproducción',
        );
        _updateState(AudioPlaybackState.playing);

        // Simular duración y completar inmediatamente
        final simulatedDuration = const Duration(milliseconds: 1000);
        Future.delayed(simulatedDuration).then((_) {
          if (_isDisposed) return; // ⭐ No procesar si está dispuesto
          _updateState(AudioPlaybackState.completed);
          if (config.notifyOnCompletion && !_completionController.isClosed) {
            _completionController.add(null);
          }
          _cleanup();
        });

        return AudioPlaybackResult.success(
          duration: simulatedDuration,
          metadata: {'simulation': true, 'reason': 'empty_audio_data'},
        );
      }

      // Crear archivo temporal
      final tempFile = await _createTempAudioFile(audioData, format);
      _currentTempFile = tempFile.path;

      // Verificar que el archivo fue creado correctamente
      if (!tempFile.existsSync() || tempFile.lengthSync() == 0) {
        Log.e('[CentralizedAudio] ❌ Archivo temporal inválido o vacío');
        throw const AudioFileException('Archivo temporal inválido');
      }

      // Configurar reproductor
      await _player.setVolume(config.volume);
      await _player.setPlaybackRate(config.speed);

      // Reproducir con manejo de errores específico para Linux
      if (config.autoPlay) {
        try {
          await _player.play(DeviceFileSource(tempFile.path));
        } on Exception catch (playError) {
          Log.e(
            '[CentralizedAudio] ❌ Error específico de reproducción en Linux: $playError',
          );

          // En Linux, algunos formatos pueden causar problemas con GStreamer
          // Intentar reproducción simulada para no bloquear el flujo
          _updateState(AudioPlaybackState.playing);

          final estimatedDuration = Duration(
            milliseconds: audioData.length ~/ 100,
          );
          Future.delayed(estimatedDuration).then((_) {
            if (_isDisposed) return; // ⭐ No procesar si está dispuesto
            _updateState(AudioPlaybackState.completed);
            if (config.notifyOnCompletion && !_completionController.isClosed) {
              _completionController.add(null);
            }
            _cleanup();
          });

          return AudioPlaybackResult.success(
            duration: estimatedDuration,
            filePath: tempFile.path,
            metadata: {
              'format': format,
              'size_bytes': audioData.length,
              'config': config.toString(),
              'linux_fallback': true,
              'original_error': playError.toString(),
            },
          );
        }
      } else {
        await _player.setSourceDeviceFile(tempFile.path);
      }

      Log.d(
        '[CentralizedAudio] ✅ Reproduciendo audio: ${audioData.length} bytes, formato: $format',
      );

      return AudioPlaybackResult.success(
        duration: _currentAudioDuration ?? Duration.zero,
        filePath: tempFile.path,
        metadata: {
          'format': format,
          'size_bytes': audioData.length,
          'config': config.toString(),
        },
      );
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error reproduciendo audio: $e');
      _updateState(AudioPlaybackState.error);

      // En lugar de lanzar excepción, devolver resultado con simulación
      // para que el onboarding conversacional no se bloquee
      Log.w(
        '[CentralizedAudio] 🔄 Usando fallback de simulación para mantener flujo',
      );

      _updateState(AudioPlaybackState.playing);
      final fallbackDuration = Duration(milliseconds: audioData.length ~/ 100);

      Future.delayed(fallbackDuration).then((_) {
        if (_isDisposed) return; // ⭐ No procesar si está dispuesto
        _updateState(AudioPlaybackState.completed);
        if (_currentConfig.notifyOnCompletion &&
            !_completionController.isClosed) {
          _completionController.add(null);
        }
        _cleanup();
      });

      return AudioPlaybackResult.success(
        duration: fallbackDuration,
        metadata: {
          'simulation': true,
          'reason': 'audio_error_fallback',
          'original_error': e.toString(),
        },
      );
    }
  }

  @override
  Future<AudioPlaybackResult> playAudioBase64({
    required final String base64Audio,
    required final String format,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  }) async {
    try {
      final audioData = base64Decode(base64Audio);
      return await playAudioBytes(
        audioData: audioData,
        format: format,
        config: config,
      );
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error decodificando base64: $e');
      throw AudioPlaybackException(
        'Error decodificando audio base64',
        originalError: e,
      );
    }
  }

  @override
  Future<AudioPlaybackResult> playAudioFile({
    required final String filePath,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  }) async {
    try {
      _currentConfig = config;
      _updateState(AudioPlaybackState.loading);

      final file = File(filePath);
      if (!file.existsSync()) {
        throw AudioFileException('Archivo no encontrado: $filePath');
      }

      // Configurar reproductor
      await _player.setVolume(config.volume);
      await _player.setPlaybackRate(config.speed);

      // Reproducir
      if (config.autoPlay) {
        await _player.play(DeviceFileSource(filePath));
      } else {
        await _player.setSourceDeviceFile(filePath);
      }

      Log.d('[CentralizedAudio] ✅ Reproduciendo archivo: $filePath');

      return AudioPlaybackResult.success(
        duration: _currentAudioDuration ?? Duration.zero,
        filePath: filePath,
        metadata: {'source': 'file', 'config': config.toString()},
      );
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error reproduciendo archivo: $e');
      _updateState(AudioPlaybackState.error);
      throw AudioPlaybackException(
        'Error reproduciendo archivo de audio',
        originalError: e,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_isDisposed) return; // ⭐ No hacer nada si está dispuesto

    try {
      await _player.stop();
      _updateState(AudioPlaybackState.stopped);
      _cleanup();
      Log.d('[CentralizedAudio] Audio detenido');
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error deteniendo audio: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      Log.d('[CentralizedAudio] Audio pausado');
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error pausando audio: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _player.resume();
      Log.d('[CentralizedAudio] Audio reanudado');
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error reanudando audio: $e');
    }
  }

  @override
  Future<void> setVolume(final double volume) async {
    try {
      final clampedVolume = volume.clamp(0.0, 1.0);
      await _player.setVolume(clampedVolume);
      Log.d(
        '[CentralizedAudio] Volumen establecido: ${(clampedVolume * 100).round()}%',
      );
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error estableciendo volumen: $e');
    }
  }

  @override
  Future<void> setSpeed(final double speed) async {
    try {
      final clampedSpeed = speed.clamp(0.1, 3.0);
      await _player.setPlaybackRate(clampedSpeed);
      Log.d('[CentralizedAudio] Velocidad establecida: ${clampedSpeed}x');
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error estableciendo velocidad: $e');
    }
  }

  /// Crear archivo temporal para reproducción
  Future<File> _createTempAudioFile(
    final List<int> audioData,
    final String format,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'centralized_audio_${DateTime.now().millisecondsSinceEpoch}.$format';
      final tempFile = File('${tempDir.path}/$fileName');

      await tempFile.writeAsBytes(audioData);

      Log.d('[CentralizedAudio] Archivo temporal creado: ${tempFile.path}');
      return tempFile;
    } on Exception catch (e) {
      Log.e('[CentralizedAudio] ❌ Error creando archivo temporal: $e');
      throw AudioFileException(
        'Error creando archivo temporal',
        originalError: e,
      );
    }
  }

  /// Limpiar archivos temporales y estado
  void _cleanup() {
    if (_currentConfig.cleanupTempFiles && _currentTempFile != null) {
      try {
        final file = File(_currentTempFile!);
        if (file.existsSync()) {
          file.deleteSync();
          Log.d(
            '[CentralizedAudio] Archivo temporal eliminado: $_currentTempFile',
          );
        }
      } on Exception catch (e) {
        Log.w('[CentralizedAudio] Error eliminando archivo temporal: $e');
      } finally {
        _currentTempFile = null;
      }
    }
    _currentAudioDuration = null;
  }

  @override
  void dispose() {
    _isDisposed = true; // ⭐ Marcar como dispuesto antes de cerrar streams

    // Detener el reproductor antes de disponer
    try {
      _player.stop();
    } on Exception catch (e) {
      Log.w('[CentralizedAudio] Error deteniendo player durante dispose: $e');
    }

    // Cerrar streams solo si no están ya cerrados
    if (!_stateController.isClosed) {
      _stateController.close();
    }
    if (!_durationController.isClosed) {
      _durationController.close();
    }
    if (!_completionController.isClosed) {
      _completionController.close();
    }

    // Disponer del player
    try {
      _player.dispose();
    } on Exception catch (e) {
      Log.w('[CentralizedAudio] Error disposing player: $e');
    }

    _cleanup();
  }
}
