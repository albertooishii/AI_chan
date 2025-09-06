import 'package:ai_chan/core/models.dart';

/// Test helper: Crea un AiChanProfile mínimo válido para tests.
/// Usar esto en lugar del ChatProvider obsoleto.
AiChanProfile createTestProfile({
  final String userName = 'TestUser',
  final String aiName = 'Ai',
}) {
  return AiChanProfile(
    userName: userName,
    aiName: aiName,
    userBirthdate: null,
    aiBirthdate: null,
    biography: <String, dynamic>{},
    appearance: <String, dynamic>{},
  );
}

/// Helper para crear mensajes de test
Message createTestMessage({
  final String text = 'Test message',
  final MessageSender sender = MessageSender.user,
}) {
  return Message(text: text, sender: sender, dateTime: DateTime.now());
}
