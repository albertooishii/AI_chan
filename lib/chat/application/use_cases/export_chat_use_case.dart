import 'package:ai_chan/chat/domain/models.dart';
import 'package:ai_chan/chat/domain/interfaces.dart';

/// Export Chat Use Case - Chat Application Layer
/// Maneja la exportación de la conversación a formato JSON
class ExportChatUseCase {
  final IChatRepository _repository;

  ExportChatUseCase({required IChatRepository repository})
    : _repository = repository;

  /// Ejecuta el caso de uso de exportación
  Future<String> execute(ChatConversation conversation) async {
    try {
      // 1. Convertir conversación a formato Map
      final conversationMap = {
        'messages': conversation.messages.map((m) => m.toJson()).toList(),
        'events': conversation.events.map((e) => e.toJson()).toList(),
        'createdAt': conversation.createdAt.toIso8601String(),
        'lastUpdatedAt': conversation.lastUpdatedAt.toIso8601String(),
      };

      // 2. Usar el repositorio para exportar a JSON string
      return await _repository.exportAllToJson(conversationMap);
    } catch (error) {
      throw Exception('Failed to export chat: $error');
    }
  }
}
