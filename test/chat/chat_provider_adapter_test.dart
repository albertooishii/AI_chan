import 'package:flutter_test/flutter_test.dart';
import '../test_setup.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import '../fakes/fake_chat_response_service.dart';

void main() async {
  await initializeTestEnvironment(prefs: {});

  test(
    'ChatProvider uses IChatResponseService adapter to append assistant message',
    () async {
      final fake = FakeChatResponseService('hola desde fake');
      final provider = ChatProvider(
        repository: null,
        chatResponseService: fake,
      );
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
    },
  );
}
