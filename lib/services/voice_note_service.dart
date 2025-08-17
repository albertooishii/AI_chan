import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../interfaces/voice_services.dart';
import '../services/voice_service_factory.dart';
import '../utils/log_utils.dart';

/// Servicio desacoplado para notas de voz usando Google STT
class VoiceNoteService {
  final STTService _sttService;
  final TTSService _ttsService;

  /// Callback para progreso de transcripción
  void Function(String status)? onProgress;

  /// Callback para resultado de transcripción
  void Function(String transcript)? onTranscript;

  /// Callback para errores
  void Function(String error)? onError;

  VoiceNoteService({STTService? sttService, TTSService? ttsService})
    : _sttService = sttService ?? VoiceServiceFactory.createSTTService(),
      _ttsService = ttsService ?? VoiceServiceFactory.createTTSService();

  /// Transcribe una nota de voz desde bytes de audio
  Future<String?> transcribeVoiceNote({required Uint8List audioData, Map<String, dynamic>? options}) async {
    try {
      Log.i('[VoiceNote] 🎤 Iniciando transcripción de nota de voz');
      Log.d('[VoiceNote] Tamaño de audio: ${audioData.length} bytes');

      onProgress?.call('Iniciando transcripción...');

      if (!_sttService.isAvailable) {
        final error = 'Servicio STT no disponible. Verifica la configuración de Google Cloud API.';
        Log.e('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }

      onProgress?.call('Enviando audio al servicio de transcripción...');

      // Configuración por defecto para notas de voz
      final defaultOptions = {
        'languageCode': 'es-ES',
        'audioEncoding': 'WEBM_OPUS',
        'sampleRateHertz': 48000,
        'enableAutomaticPunctuation': true,
      };

      // Combinar opciones
      final finalOptions = {...defaultOptions, ...(options ?? {})};

      onProgress?.call('Procesando transcripción...');

      final transcript = await _sttService.speechToText(audioData: audioData, options: finalOptions);

      if (transcript != null && transcript.trim().isNotEmpty) {
        Log.i(
          '[VoiceNote] ✅ Transcripción exitosa: "${transcript.length > 100 ? '${transcript.substring(0, 100)}...' : transcript}"',
        );
        onProgress?.call('Transcripción completada');
        onTranscript?.call(transcript);
        return transcript;
      } else {
        const error = 'No se pudo transcribir el audio. Verifica que haya sonido claro.';
        Log.w('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }
    } catch (e) {
      final error = 'Error durante la transcripción: $e';
      Log.e('[VoiceNote] $error');
      onError?.call(error);
      return null;
    }
  }

  /// Transcribe una nota de voz desde un archivo
  Future<String?> transcribeVoiceNoteFromFile({required File audioFile, Map<String, dynamic>? options}) async {
    try {
      Log.i('[VoiceNote] 📁 Transcribiendo archivo: ${audioFile.path}');

      onProgress?.call('Leyendo archivo de audio...');

      if (!await audioFile.exists()) {
        const error = 'El archivo de audio no existe';
        Log.e('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }

      final audioData = await audioFile.readAsBytes();
      Log.d('[VoiceNote] Archivo leído: ${audioData.length} bytes');

      // Determinar configuración basada en la extensión del archivo
      final extension = audioFile.path.split('.').last.toLowerCase();
      final audioEncoding = _getAudioEncodingFromExtension(extension);

      final fileOptions = {
        'audioEncoding': audioEncoding,
        'sampleRateHertz': _getSampleRateForEncoding(audioEncoding),
        ...(options ?? {}),
      };

      return await transcribeVoiceNote(audioData: audioData, options: fileOptions);
    } catch (e) {
      final error = 'Error leyendo archivo de audio: $e';
      Log.e('[VoiceNote] $error');
      onError?.call(error);
      return null;
    }
  }

  /// Crea una nota de voz desde texto (TTS)
  Future<File?> createVoiceNoteFromText({required String text, String? fileName, Map<String, dynamic>? options}) async {
    try {
      Log.i('[VoiceNote] 🔊 Creando nota de voz desde texto');
      Log.d('[VoiceNote] Texto: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"');

      onProgress?.call('Generando audio desde texto...');

      if (!_ttsService.isAvailable) {
        const error = 'Servicio TTS no disponible. Verifica la configuración de Google Cloud API.';
        Log.e('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }

      if (text.trim().isEmpty) {
        const error = 'El texto no puede estar vacío';
        Log.w('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }

      onProgress?.call('Sintetizando voz...');

      final audioFile = await _ttsService.textToSpeechFile(
        text: text.trim(),
        fileName: fileName ?? 'voice_note_${DateTime.now().millisecondsSinceEpoch}.mp3',
        options: options,
      );

      if (audioFile != null) {
        Log.i('[VoiceNote] ✅ Nota de voz creada: ${audioFile.path}');
        onProgress?.call('Nota de voz guardada');
        return audioFile;
      } else {
        const error = 'Error generando el archivo de audio';
        Log.e('[VoiceNote] $error');
        onError?.call(error);
        return null;
      }
    } catch (e) {
      final error = 'Error creando nota de voz: $e';
      Log.e('[VoiceNote] $error');
      onError?.call(error);
      return null;
    }
  }

  /// Obtiene el encoding de audio basado en la extensión del archivo
  String _getAudioEncodingFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'mp3':
        return 'MP3';
      case 'wav':
        return 'LINEAR16';
      case 'flac':
        return 'FLAC';
      case 'ogg':
      case 'opus':
        return 'OGG_OPUS';
      case 'webm':
        return 'WEBM_OPUS';
      case 'm4a':
      case 'aac':
        return 'MP3'; // Google STT no soporta AAC directamente
      default:
        Log.w('[VoiceNote] Extensión "$extension" no reconocida, usando MP3');
        return 'MP3';
    }
  }

  /// Obtiene la tasa de muestreo recomendada para el encoding
  int _getSampleRateForEncoding(String encoding) {
    switch (encoding) {
      case 'LINEAR16':
        return 16000;
      case 'WEBM_OPUS':
        return 48000;
      case 'OGG_OPUS':
        return 16000;
      case 'MP3':
        return 24000;
      case 'FLAC':
        return 16000;
      default:
        return 24000;
    }
  }

  /// Verifica si el servicio está disponible
  bool get isAvailable => _sttService.isAvailable && _ttsService.isAvailable;

  /// Obtiene información de configuración
  Map<String, dynamic> getConfig() {
    return {
      'stt': _sttService.getConfig(),
      'tts': _ttsService.getConfig(),
      'available': isAvailable,
      'supportedFormats': ['mp3', 'wav', 'flac', 'ogg', 'opus', 'webm', 'm4a', 'aac'],
    };
  }

  /// Obtiene estadísticas del servicio
  Map<String, dynamic> getStats() {
    return {
      'sttAvailable': _sttService.isAvailable,
      'ttsAvailable': _ttsService.isAvailable,
      'lastActivity': DateTime.now().toIso8601String(),
    };
  }
}
