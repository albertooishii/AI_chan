import 'dart:io';

import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_speech_service.dart';
import 'package:flutter/foundation.dart';

/// Adapter that exposes GoogleSpeechService as ISttService
class GoogleSttAdapter implements ISttService {
  const GoogleSttAdapter();

  @override
  Future<String?> transcribeAudio(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await GoogleSpeechService.speechToTextFromFile(f);
    } catch (e) {
      debugPrint('[GoogleSttAdapter] transcribeAudio error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({
    required String filePath,
    Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}
