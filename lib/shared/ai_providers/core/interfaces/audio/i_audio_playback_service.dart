import 'dart:async';
import '../../models/audio/audio_playback_state.dart';
import '../../models/audio/audio_playback_config.dart';
import '../../models/audio/audio_playback_result.dart';

/// 🎵 Interfaz principal para reproducción de audio centralizada
/// Utilizada por TTS, onboarding conversacional y sistema de llamadas
abstract class IAudioPlaybackService {
  /// Stream de estados del reproductor
  Stream<AudioPlaybackState> get stateStream;

  /// Stream que emite cuando el audio termina completamente
  Stream<void> get completionStream;

  /// Stream que emite la duración del audio cuando está disponible
  Stream<Duration> get durationStream;

  /// Estado actual del reproductor
  AudioPlaybackState get currentState;

  /// Si está reproduciendo actualmente
  bool get isPlaying;

  /// Si está pausado
  bool get isPaused;

  /// Duración del audio actual (si está disponible)
  Duration? get currentDuration;

  /// Reproducir audio desde bytes
  Future<AudioPlaybackResult> playAudioBytes({
    required final List<int> audioData,
    required final String format,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  });

  /// Reproducir audio desde base64
  Future<AudioPlaybackResult> playAudioBase64({
    required final String base64Audio,
    required final String format,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  });

  /// Reproducir audio desde archivo
  Future<AudioPlaybackResult> playAudioFile({
    required final String filePath,
    final AudioPlaybackConfig config = AudioPlaybackConfig.defaultConfig,
  });

  /// Detener reproducción
  Future<void> stop();

  /// Pausar reproducción
  Future<void> pause();

  /// Reanudar reproducción
  Future<void> resume();

  /// Establecer volumen (0.0 - 1.0)
  Future<void> setVolume(final double volume);

  /// Establecer velocidad de reproducción
  Future<void> setSpeed(final double speed);

  /// Limpiar recursos
  void dispose();
}
