import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:http/http.dart' as http;

/// Servicio híbrido de STT que usa:
/// - OpenAI STT en desktop (mejor calidad, más consistente)
/// - STT nativo en Android/iOS (mejor integración, sin latencia de red)
class HybridSttService {
  // STT nativo (Android/iOS)
  late final stt.SpeechToText _nativeStt;

  // Grabadora para OpenAI STT (Desktop)
  final AudioRecorder _recorder = AudioRecorder();

  // Control de estado
  bool _isListening = false;
  bool _isInitialized = false;

  // Callbacks
  void Function(String text)? _onResult;
  void Function(String status)? _onStatus;
  void Function(String error)? _onError;

  HybridSttService();

  /// Detecta si debe usar OpenAI STT o STT nativo
  bool get _shouldUseOpenAI {
    if (kIsWeb) return false; // Web usa nativo

    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  /// Inicializa el servicio STT apropiado para la plataforma
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;

    try {
      if (_shouldUseOpenAI) {
        Log.d('🖥️ Inicializando OpenAI STT para desktop', tag: 'HYBRID_STT');

        // Verificar permisos de micrófono para grabación
        if (await _recorder.hasPermission()) {
          _isInitialized = true;
          Log.d('✅ OpenAI STT inicializado', tag: 'HYBRID_STT');
          return true;
        } else {
          Log.e(
            '❌ Sin permisos de micrófono para OpenAI STT',
            tag: 'HYBRID_STT',
          );
          return false;
        }
      } else {
        Log.d('📱 Inicializando STT nativo para móvil', tag: 'HYBRID_STT');

        _nativeStt = stt.SpeechToText();
        _isInitialized = await _nativeStt.initialize(
          onStatus: onStatus,
          onError: onError != null
              ? (errorNotification) {
                  onError(errorNotification.errorMsg);
                }
              : null,
        );

        if (_isInitialized) {
          Log.d('✅ STT nativo inicializado', tag: 'HYBRID_STT');
        } else {
          Log.e('❌ Error inicializando STT nativo', tag: 'HYBRID_STT');
        }

        return _isInitialized;
      }
    } catch (e) {
      Log.e('Error inicializando STT híbrido: $e', tag: 'HYBRID_STT');
      return false;
    }
  }

  /// Inicia la escucha usando el método apropiado
  Future<void> listen({
    required void Function(String text) onResult,
    String localeId = 'es-ES',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isInitialized || _isListening) return;

    _onResult = onResult;
    _isListening = true;

    if (_shouldUseOpenAI) {
      await _startOpenAIListening(localeId: localeId, timeout: timeout);
    } else {
      await _startNativeListening(localeId: localeId, timeout: timeout);
    }
  }

  /// Detiene la escucha
  Future<void> stop() async {
    if (!_isListening) return;

    _isListening = false;

    if (_shouldUseOpenAI) {
      await _stopOpenAIListening();
    } else {
      await _nativeStt.stop();
    }

    Log.d('⏹️ STT detenido', tag: 'HYBRID_STT');
  }

  /// Implementación de STT usando OpenAI para desktop
  Future<void> _startOpenAIListening({
    required String localeId,
    required Duration timeout,
  }) async {
    try {
      Log.d('🎙️ Iniciando grabación para OpenAI STT...', tag: 'HYBRID_STT');

      // Configurar grabación de audio
      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      // Crear archivo temporal
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      // Iniciar grabación
      await _recorder.start(config, path: tempFile.path);
      _onStatus?.call('listening');

      // Timer de timeout
      Timer(timeout, () async {
        if (_isListening) {
          await _stopOpenAIListening();
        }
      });
    } catch (e) {
      Log.e('Error iniciando grabación OpenAI STT: $e', tag: 'HYBRID_STT');
      _onError?.call('Error iniciando grabación: $e');
      _isListening = false;
    }
  }

  /// Detiene la grabación y transcribe con OpenAI
  Future<void> _stopOpenAIListening() async {
    if (!_isListening) return;

    try {
      Log.d('⏹️ Deteniendo grabación y transcribiendo...', tag: 'HYBRID_STT');

      // Detener grabación
      final path = await _recorder.stop();

      if (path == null) {
        Log.w('No se pudo obtener archivo de audio', tag: 'HYBRID_STT');
        return;
      }

      // Transcribir con OpenAI
      final transcription = await _transcribeWithOpenAI(path);

      if (transcription.isNotEmpty) {
        Log.d('✅ Transcripción: "$transcription"', tag: 'HYBRID_STT');
        _onResult?.call(transcription);
      } else {
        Log.w('Transcripción vacía', tag: 'HYBRID_STT');
      }

      // Limpiar archivo temporal
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      Log.e('Error en transcripción OpenAI: $e', tag: 'HYBRID_STT');
      _onError?.call('Error transcribiendo: $e');
    } finally {
      _isListening = false;
      _onStatus?.call('notListening');
    }
  }

  /// Transcribe audio usando OpenAI Whisper API
  Future<String> _transcribeWithOpenAI(String audioPath) async {
    try {
      final file = File(audioPath);
      final audioBytes = await file.readAsBytes();

      Log.d(
        '📤 Enviando ${audioBytes.length} bytes a OpenAI STT',
        tag: 'HYBRID_STT',
      );

      // Crear request multipart
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );

      // Headers
      request.headers['Authorization'] = 'Bearer ${Config.getOpenAIKey()}';

      // Campos
      request.fields['model'] = Config.getOpenAISttModel();
      request.fields['language'] = 'es';
      request.fields['response_format'] = 'text';
      request.fields['temperature'] = '0.0';

      // Archivo de audio
      request.files.add(
        http.MultipartFile.fromBytes('file', audioBytes, filename: 'audio.wav'),
      );

      // Enviar request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final transcription = response.body.trim();
        return transcription;
      } else {
        Log.e(
          'Error ${response.statusCode} en OpenAI STT: ${response.body}',
          tag: 'HYBRID_STT',
        );
        return '';
      }
    } catch (e) {
      Log.e('Error transcribiendo con OpenAI: $e', tag: 'HYBRID_STT');
      return '';
    }
  }

  /// Implementación usando STT nativo para móvil
  Future<void> _startNativeListening({
    required String localeId,
    required Duration timeout,
  }) async {
    await _nativeStt.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          Log.d('✅ STT nativo: "${result.recognizedWords}"', tag: 'HYBRID_STT');
          _onResult?.call(result.recognizedWords);
        }
      },
      localeId: localeId,
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      // ignore: deprecated_member_use
      partialResults:
          false, // TODO: Migrar a SpeechListenOptions cuando sea estable
    );
  }

  /// Getters de estado
  bool get isAvailable => _isInitialized;
  bool get isListening => _isListening;
  bool get isUsingOpenAI => _shouldUseOpenAI;

  /// Limpia recursos
  void dispose() {
    stop();
    _recorder.dispose();
  }
}
