import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';

/// Fake implementation of IChatResponseService for testing
class FakeChatResponseService implements IChatResponseService {
  final String responseText;
  final String? finalModel;
  final bool? isImage;

  FakeChatResponseService(
    this.responseText, {
    this.finalModel = 'test-model',
    this.isImage = false,
  });

  @override
  Future<List<String>> getSupportedModels() async => [finalModel!];

  @override
  Future<Map<String, dynamic>> sendChat(
    List<Map<String, dynamic>> messages, {
    Map<String, dynamic>? options,
  }) async {
    return {
      'text': responseText,
      'isImage': isImage,
      'imagePath': null,
      'prompt': null,
      'seed': null,
      'finalModelUsed': options?['model'] ?? finalModel,
    };
  }
}
