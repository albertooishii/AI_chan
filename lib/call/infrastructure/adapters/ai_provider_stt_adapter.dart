import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/core/models/system_prompt.dart';
import 'package:flutter/foundation.dart';

/// Modern STT adapter using AIProviderManager
class AIProviderSttAdapter implements ICallSttService {
  const AIProviderSttAdapter();

  @override
  Future<String?> transcribeAudio(final String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;

      // Read file and convert to base64
      final audioBytes = await f.readAsBytes();
      final audioBase64 = base64Encode(audioBytes);

      debugPrint(
        '[AIProviderSttAdapter] transcribeAudio called - file size: ${audioBytes.length} bytes',
      );

      // Check if any provider supports audio transcription
      final transcriptionProviders = AIProviderManager.instance
          .getProvidersByCapability(AICapability.audioTranscription);

      if (transcriptionProviders.isNotEmpty) {
        // Create a simple history for STT
        final history = [
          {'role': 'user', 'content': 'Please transcribe this audio to text.'},
        ];

        // Create a minimal system prompt for STT
        final dummyProfile = AiChanProfile(
          userName: 'STT',
          aiName: 'AI',
          userBirthdate: DateTime.now(),
          aiBirthdate: DateTime.now(),
          appearance: {},
          biography: {},
        );
        final systemPrompt = SystemPrompt(
          profile: dummyProfile,
          dateTime: DateTime.now(),
          instructions: {
            'raw': 'Transcribe the provided audio to text accurately.',
          },
        );

        final response = await AIProviderManager.instance.sendMessage(
          history: history,
          systemPrompt: systemPrompt,
          capability: AICapability.audioTranscription,
          additionalParams: {
            'audio_base64': audioBase64,
            'audio_format': _getFileExtension(path),
            'model': Config.getOpenAISttModel(),
            'language': 'es',
          },
        );

        if (response.text.isNotEmpty) {
          debugPrint(
            '[AIProviderSttAdapter] STT success: ${response.text.length} characters',
          );
          return response.text;
        } else {
          debugPrint('[AIProviderSttAdapter] STT returned empty text');
          return null;
        }
      } else {
        debugPrint(
          '[AIProviderSttAdapter] No providers support audioTranscription capability',
        );
        return null;
      }
    } on Exception catch (e) {
      debugPrint('[AIProviderSttAdapter] transcribeAudio error: $e');
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

  @override
  Future<String> processAudio(final Uint8List audioData) async {
    try {
      // Crear archivo temporal para procesar audio
      final tempFile = File(
        '${Directory.systemTemp.path}/temp_ai_provider_audio.wav',
      );
      await tempFile.writeAsBytes(audioData);
      final result = await transcribeAudio(tempFile.path);
      await tempFile.delete();
      return result ?? '';
    } on Exception catch (e) {
      debugPrint('[AIProviderSttAdapter] processAudio error: $e');
      return '';
    }
  }

  @override
  void configure(final Map<String, dynamic> config) {
    debugPrint('[AIProviderSttAdapter] Configured with: $config');
  }

  @override
  Future<bool> isAvailable() async {
    // Check if we have any STT capability available
    final transcriptionProviders = AIProviderManager.instance
        .getProvidersByCapability(AICapability.audioTranscription);
    return transcriptionProviders.isNotEmpty;
  }

  /// Get file extension from path
  String _getFileExtension(final String path) {
    final parts = path.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return 'wav'; // Default format
  }
}
