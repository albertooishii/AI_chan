import '../test_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import '../fakes/fake_chat_response_service.dart';

void main() async {
  await initializeTestEnvironment();

  test(
    'ChatProvider sendMessage updates statuses and appends assistant message',
    () async {
      final provider = ChatProvider(
        repository: null,
        chatResponseService: FakeChatResponseService('Respuesta de prueba'),
      );
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
    },
  );
}
