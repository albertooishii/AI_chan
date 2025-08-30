import 'dart:io';

import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/shared/services/openai_service.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart' as runtime_factory;
import 'package:ai_chan/core/config.dart';
import 'package:flutter/foundation.dart';

/// Adapter that exposes OpenAIService.transcribeAudio as ISttService
class OpenAISttAdapter implements ISttService {
  const OpenAISttAdapter();

  @override
  Future<String?> transcribeAudio(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
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
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('[OpenAISttAdapter] transcribeAudio error: $e');
      return null;
    }
  }

  @override
  Future<String?> transcribeFile({required String filePath, Map<String, dynamic>? options}) async {
    return await transcribeAudio(filePath);
  }
}
