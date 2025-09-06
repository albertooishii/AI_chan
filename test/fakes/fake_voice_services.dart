import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';

/// Fake STT service for testing voice-related functionality
class FakeSttService implements ISttService {
  FakeSttService({
    this.transcriptionResult = 'transcripcion de prueba',
    this.shouldFail = false,
  });
  final String transcriptionResult;
  final bool shouldFail;

  @override
  Future<String?> transcribeAudio(final String path) async {
    if (shouldFail) throw Exception('STT failed');
    return transcriptionResult;
  }

  @override
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}

/// Fake AI service for calls/voice testing
class FakeCallsAiService implements IAIService {
  FakeCallsAiService({
    this.response = 'respuesta generada por ai',
    this.models = const ['gemi-test'],
  });
  final String response;
  final List<String> models;

  @override
  Future<Map<String, dynamic>> sendMessage({
    required final List<Map<String, dynamic>> messages,
    final Map<String, dynamic>? options,
  }) async {
    return {'text': response};
  }

  @override
  Future<List<String>> getAvailableModels() async => models;

  @override
  Future<String?> textToSpeech(
    final String text, {
    final String voice = '',
    final Map<String, dynamic>? options,
  }) async => null;
}
