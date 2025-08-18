import 'dart:io';

import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/services/google_speech_service.dart';
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
}
