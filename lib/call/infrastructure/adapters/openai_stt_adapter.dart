import 'dart:io';

import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/shared/services/enhanced_ai_runtime_provider.dart';
import 'package:ai_chan/core/config.dart';
import 'package:flutter/foundation.dart';

/// Adapter that exposes OpenAIService.transcribeAudio as ICallSttService
class OpenAISttAdapter implements ICallSttService {
  const OpenAISttAdapter();

  @override
  Future<String?> transcribeAudio(final String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;

      // Use Enhanced AI Runtime Provider for STT
      final modelForStt = Config.getOpenAISttModel();
      await EnhancedAIRuntimeProvider.initialize();
      // TODO: Implement STT in Enhanced AI system

      // Enhanced AI doesn't support STT yet - return null for now
      debugPrint(
        '[OpenAISttAdapter] Enhanced AI STT not implemented yet for model: $modelForStt',
      );
      return null;
    } on Exception catch (e) {
      debugPrint('[OpenAISttAdapter] Enhanced AI error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }

  // Implementación de ISttAdapter
  @override
  Future<String> processAudio(final Uint8List audioData) async {
    try {
      // Crear archivo temporal para procesar audio
      final tempFile = File(
        '${Directory.systemTemp.path}/temp_openai_audio.wav',
      );
      await tempFile.writeAsBytes(audioData);
      final result = await transcribeAudio(tempFile.path);
      await tempFile.delete();
      return result ?? '';
    } on Exception catch (e) {
      debugPrint('[OpenAISttAdapter] processAudio error: $e');
      return '';
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[OpenAISttAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    return Config.get('OPENAI_API_KEY', '').trim().isNotEmpty;
  }
}
