import 'dart:typed_data';
import 'dart:io';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';

/// Adaptador para GoogleSpeechService que implementa ICallTtsService
class GoogleTtsAdapter implements ICallTtsService {
  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    try {
      final voice = options?['voice'] as String? ?? 'es-ES-Wavenet-F';
      final speed = options?['speed'] as double? ?? 1.0;
      final languageCode = options?['languageCode'] as String? ?? 'es-ES';

      final file = await GoogleSpeechService.textToSpeechFileStatic(
        text: text,
        voiceName: voice,
        languageCode: languageCode,
        speakingRate: speed,
        useCache: true,
      );

      return file?.path;
    } on Exception {
      return null;
    }
  }

  @override
  Future<Uint8List> synthesize({
    required final String text,
    final String voice = 'default',
    final double speed = 1.0,
  }) async {
    try {
      final normalizedVoice = voice == 'default' ? 'es-ES-Wavenet-F' : voice;

      final audioData = await GoogleSpeechService.textToSpeechStatic(
        text: text,
        voiceName: normalizedVoice,
        speakingRate: speed,
        useCache: true,
      );

      return audioData ?? Uint8List(0);
    } on Exception {
      return Uint8List(0);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      return await GoogleSpeechService.fetchGoogleVoicesStatic();
    } on Exception {
      return [];
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return GoogleSpeechService.isConfiguredStatic;
    } on Exception {
      return false;
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    // GoogleSpeechService no tiene configuración específica por instancia
    // La configuración se maneja a través de métodos estáticos
  }
}

/// Adaptador para GoogleSpeechService que implementa ICallSttService
class GoogleSttAdapter implements ICallSttService {
  @override
  Future<String?> transcribeAudio(final String filePath) async {
    try {
      final file = File(filePath);
      return await GoogleSpeechService.speechToTextFromFileStatic(file);
    } on Exception {
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    try {
      final file = File(filePath);
      final languageCode = options?['languageCode'] as String? ?? 'es-ES';

      return await GoogleSpeechService.speechToTextFromFileStatic(
        file,
        languageCode: languageCode,
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<String> processAudio(final Uint8List audioData) async {
    try {
      final result = await GoogleSpeechService.speechToTextStatic(
        audioData: audioData,
      );

      return result ?? '';
    } on Exception {
      return '';
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    // GoogleSpeechService no tiene configuración específica por instancia
    // La configuración se maneja a través de métodos estáticos
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return GoogleSpeechService.isConfiguredStatic;
    } on Exception {
      return false;
    }
  }
}
