import 'package:ai_chan/chat/domain/models/chat_conversation.dart';
import 'package:ai_chan/chat/domain/models/message.dart';
import 'package:ai_chan/chat/domain/models/chat_event.dart';

/// Chat Service - Domain Service Interface
/// Define los casos de uso principales del dominio de chat.
/// Esta interfaz representa las operaciones de negocio principales del chat.
abstract class IChatService {
  /// Envía un mensaje y procesa la respuesta del asistente
  Future<ChatConversation> sendMessage(
    ChatConversation conversation,
    Message userMessage,
  );

  /// Carga el historial de conversación completo
  Future<ChatConversation> loadConversation();

  /// Guarda la conversación actual
  Future<void> saveConversation(ChatConversation conversation);

  /// Agrega un evento a la conversación
  Future<ChatConversation> addEvent(
    ChatConversation conversation,
    ChatEvent event,
  );

  /// Exporta la conversación a formato JSON
  Future<String> exportConversation(ChatConversation conversation);

  /// Importa una conversación desde JSON
  Future<ChatConversation> importConversation(String jsonString);

  /// Limpia toda la conversación
  Future<void> clearConversation();
}
