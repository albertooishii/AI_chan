import 'dart:io';

import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/shared/services/openai_service.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart' as runtime_factory;
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
      // Use the centralized runtime factory so singletons and config are respected.
      final modelForStt = Config.getOpenAISttModel();
      final svc = runtime_factory.getRuntimeAIServiceForModel(modelForStt);
      if (svc is OpenAIService) {
        return await svc.transcribeAudio(path);
      }
      // If runtime factory returned a different implementation, attempt a dynamic call
      try {
        final dynamic dyn = svc;
        if (dyn != null && dyn.transcribeAudio != null) {
          return await dyn.transcribeAudio(path);
        }
      } on Exception catch (_) {}
      return null;
    } on Exception catch (e) {
      debugPrint('[OpenAISttAdapter] transcribeAudio error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({required final String filePath, final Map<String, dynamic>? options}) async {
    return await transcribeAudio(filePath);
  }

  // Implementación de ISttAdapter
  @override
  Future<String> processAudio(final Uint8List audioData) async {
    try {
      // Crear archivo temporal para procesar audio
      final tempFile = File('${Directory.systemTemp.path}/temp_openai_audio.wav');
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
