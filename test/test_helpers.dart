import 'package:ai_chan/core/models.dart';

/// Test helper: Crea un AiChanProfile mínimo válido para tests.
/// Usar esto en lugar del ChatProvider obsoleto.
AiChanProfile createTestProfile({String userName = 'TestUser', String aiName = 'Ai'}) {
  return AiChanProfile(
    userName: userName,
    aiName: aiName,
    userBirthdate: null,
    aiBirthdate: null,
    biography: <String, dynamic>{},
    appearance: <String, dynamic>{},
    timeline: <TimelineEntry>[],
  );
}

/// Helper para crear mensajes de test
Message createTestMessage({String text = 'Test message', MessageSender sender = MessageSender.user}) {
  return Message(text: text, sender: sender, dateTime: DateTime.now());
}
