import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as ap;

import '../../domain/interfaces/audio_playback_service.dart';
import '../../ai_providers/core/services/audio/centralized_audio_playback_service.dart';

/// 🎵 Adapter que conecta AudioPlaybackService con CentralizedAudioPlaybackService
/// Usado en TTS configuration dialog para compatibilidad
class AudioPlaybackServiceAdapter implements AudioPlaybackService {
  AudioPlaybackServiceAdapter() {
    _centralizedService = CentralizedAudioPlaybackService.instance;
  }

  late final CentralizedAudioPlaybackService _centralizedService;

  @override
  Stream<void> get onPlayerComplete => _centralizedService.completionStream;

  @override
  Stream<Duration> get onDurationChanged => _centralizedService.durationStream;

  @override
  Stream<Duration> get onPositionChanged {
    // CentralizedAudioPlaybackService no expone position stream directamente
    // Retornamos un stream vacío por compatibilidad
    return const Stream<Duration>.empty();
  }

  @override
  Future<void> play(final dynamic source) async {
    if (source is ap.Source) {
      // Manejar diferentes tipos de fuentes de audioplayers
      if (source is ap.DeviceFileSource) {
        await _centralizedService.playAudioFile(filePath: source.path);
      } else if (source is ap.UrlSource) {
        // Para URLs, podríamos implementar descarga temporal o usar otro approach
        throw UnsupportedError('URL sources not supported in adapter yet');
      } else if (source is ap.BytesSource) {
        await _centralizedService.playAudioBytes(
          audioData: source.bytes,
          format: 'mp3', // Asumimos mp3 por defecto
        );
      }
    } else if (source is String) {
      // Asumimos que es un path de archivo
      await _centralizedService.playAudioFile(filePath: source);
    } else {
      throw ArgumentError('Unsupported source type: ${source.runtimeType}');
    }
  }

  @override
  Future<void> stop() async {
    await _centralizedService.stop();
  }

  @override
  Future<void> dispose() async {
    // CentralizedAudioPlaybackService es singleton, no lo disponemos
    // Solo detenemos si está reproduciendo
    if (_centralizedService.isPlaying) {
      await _centralizedService.stop();
    }
  }

  @override
  Future<void> setReleaseMode(final dynamic mode) async {
    // CentralizedAudioPlaybackService maneja esto internamente
    // No hacemos nada por compatibilidad
  }
}
