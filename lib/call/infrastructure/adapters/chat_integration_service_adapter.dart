import 'package:ai_chan/call/domain/interfaces/i_chat_integration_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

/// Implementación del servicio de integración con chat
/// Actúa como adapter entre el contexto de call y chat
class ChatIntegrationServiceAdapter implements IChatIntegrationService {
  const ChatIntegrationServiceAdapter(this._chatRepository);
  final IChatRepository _chatRepository;

  @override
  Future<Map<String, dynamic>?> getLastMessage() async {
    try {
      final chatData = await _chatRepository.loadAll();
      if (chatData == null) return null;

      final messages = chatData['messages'] as List<dynamic>? ?? [];
      if (messages.isEmpty) return null;

      final lastMessage = messages.last as Map<String, dynamic>;
      return convertMessageData(lastMessage);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getMessageHistory({
    final int limit = 10,
  }) async {
    try {
      final chatData = await _chatRepository.loadAll();
      if (chatData == null) return [];

      final messages = chatData['messages'] as List<dynamic>? ?? [];
      final limitedMessages = messages.take(limit).toList();

      return limitedMessages
          .map(
            (final message) =>
                convertMessageData(message as Map<String, dynamic>),
          )
          .toList();
    } on Exception {
      return [];
    }
  }

  @override
  Map<String, dynamic> convertMessageData(
    final Map<String, dynamic> messageData,
  ) {
    // Convierte el formato de mensaje de chat al formato esperado por call
    return {
      'id': messageData['localId'] ?? '',
      'content': messageData['text'] ?? '',
      'author': messageData['sender'] == 'user' ? 'user' : 'assistant',
      'timestamp': messageData['dateTime'] ?? DateTime.now().toIso8601String(),
      'isUser': messageData['sender'] == 'user',
      'isAssistant': messageData['sender'] == 'assistant',
    };
  }
}
