import 'dart:async';
import 'dart:io';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/infrastructure/audio/audio_playback.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/audio_duration_utils.dart';

/// Servicio de TTS directo de OpenAI sin streaming
/// Sintetiza el texto completo de una vez y luego lo reproduce con subtítulos progresivos
class OpenAITtsService {
  bool _isPlaying = false;
  String? _currentAudioPath;
  Duration? _currentAudioDuration;
  Completer<void>? _completionCompleter;

  // 🎵 Usar instancia persistente como en el chat
  final AudioPlayback _audioPlayer = di.getAudioPlayback();

  OpenAITtsService();

  /// Sintetiza y reproduce texto usando OpenAI TTS directo (sin streaming)
  /// Retorna información del audio generado para subtítulos progresivos
  Future<AudioPlaybackInfo?> synthesizeAndPlay(
    String text, {
    Map<String, dynamic>? options,
  }) async {
    try {
      _isPlaying = true;
      _completionCompleter =
          Completer<void>(); // Inicializar completer para cancelación

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

          // Iniciar reproducción con la instancia persistente
          await _audioPlayer.play(audioFile);

          Log.d('🔊 Reproducción iniciada', tag: 'OPENAI_TTS');

          // Programar completion después de la duración del audio
          Timer(audioDuration, () {
            if (_completionCompleter != null &&
                !_completionCompleter!.isCompleted) {
              _completionCompleter!.complete();
            }
          });

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
      // Completar el completer en caso de error
      if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
        _completionCompleter!.completeError(e);
      }
      Log.e('❌ Error en synthesizeAndPlay: $e', tag: 'OPENAI_TTS');
      rethrow;
    }
  }

  /// Espera a que termine la reproducción actual (cancelable)
  Future<void> waitForCompletion() async {
    if (!_isPlaying || _completionCompleter == null) return;

    Log.d('⏳ Esperando finalización de reproducción...', tag: 'OPENAI_TTS');

    try {
      await _completionCompleter!.future;
    } catch (e) {
      Log.w('Reproducción cancelada o error: $e', tag: 'OPENAI_TTS');
    }

    // Limpiar archivo temporal después de la reproducción
    await _cleanupCurrentAudio();

    _isPlaying = false;
    _completionCompleter = null;
    Log.d('✅ Reproducción completada', tag: 'OPENAI_TTS');
  }

  /// Limpia el archivo de audio actual
  Future<void> _cleanupCurrentAudio() async {
    if (_currentAudioPath != null) {
      try {
        final audioFile = File(_currentAudioPath!);

        // NO eliminar archivos de caché persistente - solo temporales
        if (_currentAudioPath!.contains('AI_chan_cache')) {
          Log.d(
            '💾 Archivo de caché persistente conservado: $_currentAudioPath',
            tag: 'OPENAI_TTS',
          );
        } else if (await audioFile.exists()) {
          // Solo eliminar archivos temporales
          await audioFile.delete();
          Log.d(
            '🗑️ Archivo TTS temporal eliminado: $_currentAudioPath',
            tag: 'OPENAI_TTS',
          );
        }
      } catch (e) {
        Log.w('Error procesando archivo temporal: $e', tag: 'OPENAI_TTS');
      }
      _currentAudioPath = null;
      _currentAudioDuration = null;
    }
  }

  /// Detiene la reproducción actual
  Future<void> stop() async {
    try {
      Log.d('🛑 INICIANDO STOP - _isPlaying: $_isPlaying', tag: 'OPENAI_TTS');

      // 🎵 Usar la misma instancia persistente como en el chat
      Log.d('🛑 Llamando _audioPlayer.stop()...', tag: 'OPENAI_TTS');
      await _audioPlayer.stop();
      Log.d('✅ _audioPlayer.stop() completado', tag: 'OPENAI_TTS');

      // Cancelar el completer si existe
      if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
        Log.d('🛑 Completando _completionCompleter...', tag: 'OPENAI_TTS');
        _completionCompleter!
            .complete(); // Completar inmediatamente para liberar waitForCompletion
      }

      await _cleanupCurrentAudio();
      _isPlaying = false;
      _completionCompleter = null;
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
    // Cancelar completer si existe
    if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
      _completionCompleter!.complete();
    }
    _completionCompleter = null;
    _cleanupCurrentAudio();

    // Limpiar reproductor de audio
    try {
      _audioPlayer.dispose();
      Log.d('🧹 Limpiando recursos OpenAI TTS', tag: 'OPENAI_TTS');
    } catch (e) {
      Log.e('❌ Error liberando recursos OpenAI TTS: $e', tag: 'OPENAI_TTS');
    }
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
