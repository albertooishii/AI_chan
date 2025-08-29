import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';

/// Test helper: crea un ChatProvider con un `onboardingData` mínimo válido.
ChatProvider createTestChatProvider({AiChanProfile? profile}) {
  final provider = ChatProvider();
  provider.onboardingData =
      profile ??
      AiChanProfile(
        userName: 'TestUser',
        aiName: 'Ai',
        userBirthday: null,
        aiBirthday: null,
        biography: <String, dynamic>{},
        appearance: <String, dynamic>{},
        timeline: <TimelineEntry>[],
      );
  return provider;
}
