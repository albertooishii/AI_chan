import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/http_connector.dart';

/// Servicio para streaming de TTS usando OpenAI con reproducción en tiempo real
/// Reutiliza la arquitectura de llamadas para máxima eficiencia
class StreamingTtsService {
  final AudioPlayer _audioPlayer;
  final List<int> _audioBuffer = [];
  bool _isStreaming = false;
  StreamSubscription<PlayerState>? _playerSub;
  Completer<void>? _playbackCompleter;

  StreamingTtsService({AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer();

  /// Sintetiza y reproduce texto usando streaming de OpenAI TTS
  Future<bool> streamAndPlay({
    required String text,
    String voice = 'marin',
    Map<String, dynamic>? options,
  }) async {
    if (text.trim().isEmpty) return false;

    // Extraer opciones
    final model = options?['model'] as String? ?? 'gpt-4o-mini-tts';
    final instructions = options?['instructions'] as String?;
    final speed = options?['speed'] as double? ?? 1.0;

    Log.d(
      '🎵 Iniciando streaming TTS: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
      tag: 'STREAMING_TTS',
    );

    // Limpiar buffer anterior
    _audioBuffer.clear();
    _isStreaming = true;

    try {
      // Configurar completer para esperar finalización
      _playbackCompleter = Completer<void>();

      // Configurar listener de audio player
      _setupAudioPlayerListener();

      // Iniciar streaming desde OpenAI
      await _startOpenAIStreaming(
        text: text,
        voice: voice,
        model: model,
        instructions: instructions,
        speed: speed,
      );

      // Esperar a que termine la reproducción
      await _playbackCompleter?.future;

      return true; // Streaming exitoso
    } catch (e) {
      Log.e('Error en streaming TTS: $e', tag: 'STREAMING_TTS');
      _isStreaming = false;
      return false; // Falló, se puede intentar método tradicional
    } finally {
      _isStreaming = false;
      await _playerSub?.cancel();
      _playerSub = null;
    }
  }

  /// Configura el listener del AudioPlayer (reutilizado de CallController)
  void _setupAudioPlayerListener() {
    _playerSub?.cancel();
    _playerSub = _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      Log.d('🎵 Audio player state: $state', tag: 'STREAMING_TTS');

      if (state == PlayerState.completed) {
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
        }
      }
    });
  }

  /// Inicia streaming desde OpenAI TTS (adaptado de OpenAIRealtimeClient)
  Future<void> _startOpenAIStreaming({
    required String text,
    required String voice,
    required String model,
    String? instructions,
    required double speed,
  }) async {
    final apiKey = Config.getOpenAIKey();
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI para streaming TTS');
    }

    // Preparar request body (basado en openai_service.dart)
    final Map<String, dynamic> requestBody = {
      'model': model,
      'input': text,
      'voice': voice,
      'response_format': 'wav', // WAV para menor latencia según documentación
      'speed': speed,
    };

    // Agregar instructions si están presentes (nueva feature de OpenAI)
    if (instructions != null && instructions.trim().isNotEmpty) {
      requestBody['instructions'] = instructions.trim();
    }

    Log.d('🚀 Iniciando request streaming a OpenAI TTS', tag: 'STREAMING_TTS');
    Log.d('📝 Request body: $requestBody', tag: 'STREAMING_TTS');

    try {
      // Usar HttpConnector.client para consistencia (adaptado del código existente)
      final response = await HttpConnector.client.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        Log.d(
          '✅ OpenAI TTS response recibido: ${response.bodyBytes.length} bytes',
          tag: 'STREAMING_TTS',
        );

        // Cargar todos los bytes al buffer (para esta primera versión, luego optimizaremos el streaming real)
        _audioBuffer.addAll(response.bodyBytes);

        // Iniciar reproducción inmediatamente
        await _startPlayback();

        Log.d(
          '📡 TTS completado: ${_audioBuffer.length} bytes procesados',
          tag: 'STREAMING_TTS',
        );
      } else {
        throw Exception(
          'OpenAI TTS error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      Log.e('Error en request TTS: $e', tag: 'STREAMING_TTS');
      rethrow;
    }
  }

  /// Inicia reproducción del buffer acumulado (basado en CallController._startPlayback)
  Future<void> _startPlayback() async {
    if (_audioBuffer.isEmpty) return;

    Log.d(
      '🎵 Iniciando reproducción de ${_audioBuffer.length} bytes',
      tag: 'STREAMING_TTS',
    );

    try {
      // Crear archivo temporal con el buffer actual
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/streaming_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      // Escribir datos de audio
      await tempFile.writeAsBytes(Uint8List.fromList(_audioBuffer));

      Log.d(
        '📁 Archivo temporal creado: ${tempFile.path}',
        tag: 'STREAMING_TTS',
      );

      // Reproducir archivo
      await _audioPlayer.play(DeviceFileSource(tempFile.path));

      Log.d('▶️ Reproducción iniciada', tag: 'STREAMING_TTS');

      // Limpiar archivo temporal después de un tiempo
      Timer(const Duration(seconds: 30), () async {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
            Log.d('🗑️ Archivo temporal limpiado', tag: 'STREAMING_TTS');
          }
        } catch (e) {
          Log.w('Error limpiando archivo temporal: $e', tag: 'STREAMING_TTS');
        }
      });
    } catch (e) {
      Log.e('Error iniciando reproducción: $e', tag: 'STREAMING_TTS');
      // Completar playback en caso de error
      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.completeError(e);
      }
    }
  }

  /// Detiene el streaming y reproducción
  Future<void> stop() async {
    _isStreaming = false;

    try {
      await _audioPlayer.stop();
      Log.d('⏹️ Streaming TTS detenido', tag: 'STREAMING_TTS');
    } catch (e) {
      Log.w('Error deteniendo audio player: $e', tag: 'STREAMING_TTS');
    }

    // Completar playback completer si aún está pendiente
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }

    await _playerSub?.cancel();
    _playerSub = null;
  }

  /// Limpia recursos
  void dispose() {
    stop();
    _audioBuffer.clear();
  }

  /// Verifica si está reproduciendo actualmente
  bool get isPlaying => _isStreaming;
}
