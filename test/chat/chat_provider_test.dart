import '../test_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';

// Usamos un fake ChatResponseService simple que responde con texto inmediato
class FakeChatResponseService implements IChatResponseService {
  @override
  Future<Map<String, dynamic>> sendChat(List<Map<String, dynamic>> messages, {Map<String, dynamic>? options}) async {
    return {
      'text': 'Respuesta de prueba',
      'isImage': false,
      'imagePath': null,
      'prompt': null,
      'seed': null,
      'finalModelUsed': options?['model'] ?? 'test-model',
    };
  }

  @override
  Future<List<String>> getSupportedModels() async => ['test-model'];
}

void main() async {
  await initializeTestEnvironment();

  test('ChatProvider sendMessage updates statuses and appends assistant message', () async {
    final provider = ChatProvider(chatResponseService: FakeChatResponseService());
    provider.onboardingData = AiChanProfile(
      events: [],
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      biography: {},
      appearance: {},
      timeline: [],
    );
    expect(provider.messages.length, 0);
    await provider.sendMessage('hola');
    // Último mensaje debe ser del assistant
    expect(provider.messages.isNotEmpty, true);
    expect(provider.messages.last.sender, MessageSender.assistant);
    expect(provider.messages.last.status, MessageStatus.read);
  });
}
