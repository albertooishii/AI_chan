import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';

/// Fake STT service for testing voice-related functionality
class FakeSttService implements ISttService {
  final String transcriptionResult;
  final bool shouldFail;

  FakeSttService({
    this.transcriptionResult = 'transcripcion de prueba',
    this.shouldFail = false,
  });

  @override
  Future<String?> transcribeAudio(String path) async {
    if (shouldFail) throw Exception('STT failed');
    return transcriptionResult;
  }

  @override
  Future<String?> transcribeFile({
    required String filePath,
    Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}

/// Fake AI service for calls/voice testing
class FakeCallsAiService implements IAIService {
  final String response;
  final List<String> models;

  FakeCallsAiService({
    this.response = 'respuesta generada por ai',
    this.models = const ['gemi-test'],
  });

  @override
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  }) async {
    return {'text': response};
  }

  @override
  Future<List<String>> getAvailableModels() async => models;

  @override
  Future<String?> textToSpeech(
    String text, {
    String voice = '',
    Map<String, dynamic>? options,
  }) async => null;
}
