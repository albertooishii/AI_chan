import 'package:flutter_test/flutter_test.dart';
import '../test_setup.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';

class FakeChatResponseService implements IChatResponseService {
  final String responseText;
  FakeChatResponseService(this.responseText);

  @override
  Future<List<String>> getSupportedModels() async => ['fake-model'];

  @override
  Future<Map<String, dynamic>> sendChat(List<Map<String, dynamic>> messages, {Map<String, dynamic>? options}) async {
    return {'text': responseText, 'isImage': false};
  }
}

void main() async {
  await initializeTestEnvironment(prefs: {});

  test('ChatProvider uses IChatResponseService adapter to append assistant message', () async {
    final fake = FakeChatResponseService('hola desde fake');
    final provider = ChatProvider(repository: null, chatResponseService: fake);
    provider.onboardingData = AiChanProfile.fromJson({
      'userName': 'u',
      'aiName': 'ai',
      'biography': {},
      'appearance': {},
      'timeline': [],
    });

    // Enviar mensaje de usuario
    await provider.sendMessage('hola');

    // El último mensaje debería ser del assistant con el text del fake
    final last = provider.messages.last;
    expect(last.sender, MessageSender.assistant);
    expect(last.text.contains('hola desde fake'), true);
  });
}
