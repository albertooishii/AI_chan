import 'dart:async';
import 'dart:io';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/audio_duration_utils.dart';

/// Servicio de TTS directo de OpenAI sin streaming
/// Sintetiza el texto completo de una vez y luego lo reproduce con subtítulos progresivos
class OpenAITtsService {
  bool _isPlaying = false;
  String? _currentAudioPath;
  Duration? _currentAudioDuration;

  OpenAITtsService();

  /// Sintetiza y reproduce texto usando OpenAI TTS directo (sin streaming)
  /// Retorna información del audio generado para subtítulos progresivos
  Future<AudioPlaybackInfo?> synthesizeAndPlay(
    String text, {
    Map<String, dynamic>? options,
  }) async {
    try {
      _isPlaying = true;

      // Configurar opciones por defecto para OpenAI
      final ttsOptions = {
        'provider': 'openai',
        'voice': 'marin',
        'speed': 1.0,
        ...?options, // Mezclar opciones adicionales si se proporcionan
      };

      Log.d(
        '🎵 Sintetizando con OpenAI TTS: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."',
        tag: 'OPENAI_TTS',
      );
      Log.d('🔧 Opciones TTS: $ttsOptions', tag: 'OPENAI_TTS');

      // Usar el servicio TTS con proveedor explícito OpenAI
      final audioFile = await di.getTtsService().synthesizeToFile(
        text: text,
        options: ttsOptions,
      );

      if (audioFile != null) {
        Log.d('✅ Audio sintetizado: $audioFile', tag: 'OPENAI_TTS');

        // Obtener duración real del archivo
        final audioDuration = await AudioDurationUtils.getAudioDuration(
          audioFile,
        );

        if (audioDuration != null && audioDuration.inMilliseconds > 0) {
          Log.d(
            '⏰ Duración real del audio: ${audioDuration.inMilliseconds}ms',
            tag: 'OPENAI_TTS',
          );

          _currentAudioPath = audioFile;
          _currentAudioDuration = audioDuration;

          // Iniciar reproducción
          final audioPlayback = di.getAudioPlayback();
          await audioPlayback.play(audioFile);

          Log.d('🔊 Reproducción iniciada', tag: 'OPENAI_TTS');

          // Retornar información para subtítulos progresivos
          return AudioPlaybackInfo(
            audioPath: audioFile,
            duration: audioDuration,
            text: text,
          );
        } else {
          Log.e('❌ No se pudo obtener duración del audio', tag: 'OPENAI_TTS');
          throw Exception('No se pudo obtener duración del audio');
        }
      } else {
        Log.e('❌ No se pudo sintetizar el audio', tag: 'OPENAI_TTS');
        throw Exception('No se pudo sintetizar el audio con OpenAI TTS');
      }
    } catch (e) {
      _isPlaying = false;
      _currentAudioPath = null;
      _currentAudioDuration = null;
      Log.e('❌ Error en synthesizeAndPlay: $e', tag: 'OPENAI_TTS');
      rethrow;
    }
  }

  /// Espera a que termine la reproducción actual
  Future<void> waitForCompletion() async {
    if (!_isPlaying || _currentAudioDuration == null) return;

    Log.d('⏳ Esperando finalización de reproducción...', tag: 'OPENAI_TTS');
    await Future.delayed(_currentAudioDuration!);

    // Limpiar archivo temporal después de la reproducción
    await _cleanupCurrentAudio();

    _isPlaying = false;
    Log.d('✅ Reproducción completada', tag: 'OPENAI_TTS');
  }

  /// Limpia el archivo de audio actual
  Future<void> _cleanupCurrentAudio() async {
    if (_currentAudioPath != null) {
      try {
        final audioFile = File(_currentAudioPath!);
        if (await audioFile.exists()) {
          await audioFile.delete();
          Log.d(
            '🗑️ Archivo TTS temporal eliminado: $_currentAudioPath',
            tag: 'OPENAI_TTS',
          );
        }
      } catch (e) {
        Log.w('Error eliminando archivo temporal: $e', tag: 'OPENAI_TTS');
      }
      _currentAudioPath = null;
      _currentAudioDuration = null;
    }
  }

  /// Detiene la reproducción actual
  Future<void> stop() async {
    try {
      final audioPlayback = di.getAudioPlayback();
      await audioPlayback.stop();
      await _cleanupCurrentAudio();
      _isPlaying = false;
      Log.d('⏹️ Reproducción detenida', tag: 'OPENAI_TTS');
    } catch (e) {
      Log.e('❌ Error deteniendo TTS: $e', tag: 'OPENAI_TTS');
    }
  }

  /// Verifica si está reproduciendo audio actualmente
  bool get isPlaying => _isPlaying;

  /// Obtiene la duración del audio actual
  Duration? get currentDuration => _currentAudioDuration;

  /// Limpia los recursos
  void dispose() {
    _cleanupCurrentAudio();
    Log.d('🧹 Limpiando recursos OpenAI TTS', tag: 'OPENAI_TTS');
  }
}

/// Información de reproducción de audio para subtítulos progresivos
class AudioPlaybackInfo {
  final String audioPath;
  final Duration duration;
  final String text;

  const AudioPlaybackInfo({
    required this.audioPath,
    required this.duration,
    required this.text,
  });
}
