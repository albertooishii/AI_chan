import 'dart:io';

import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/services/google_speech_service.dart';
import 'package:flutter/foundation.dart';

/// Adapter that exposes GoogleSpeechService as ICallSttService
class GoogleSttAdapter implements ICallSttService {
  const GoogleSttAdapter();

  @override
  Future<String?> transcribeAudio(final String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return await GoogleSpeechService.speechToTextFromFileStatic(f.path);
    } on Exception catch (e) {
      debugPrint('[GoogleSttAdapter] transcribeAudio error: $e');
      return null;
    }
  }

  // ISttAdapter implementation
  @override
  Future<String> processAudio(final Uint8List audioData) async {
    // Convert audio data to file temporarily and process
    try {
      final tempFile = File('${Directory.systemTemp.path}/temp_audio.wav');
      await tempFile.writeAsBytes(audioData);
      final result = await GoogleSpeechService.speechToTextFromFileStatic(
        tempFile.path,
      );
      await tempFile.delete();
      return result ?? '';
    } on Exception catch (e) {
      debugPrint('[GoogleSttAdapter] processAudio error: $e');
      return '';
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    // Google STT adapter configuration if needed
    debugPrint('[GoogleSttAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    return GoogleSpeechService.apiKey.isNotEmpty;
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}
