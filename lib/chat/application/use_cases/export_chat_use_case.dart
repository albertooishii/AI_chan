import 'package:ai_chan/chat.dart';

/// Export Chat Use Case - Chat Application Layer
/// Maneja la exportación de la conversación a formato JSON
class ExportChatUseCase {
  ExportChatUseCase({required final IChatRepository repository})
    : _repository = repository;
  final IChatRepository _repository;

  /// Ejecuta el caso de uso de exportación
  Future<String> execute(final ChatConversation conversation) async {
    try {
      // 1. Convertir conversación a formato Map
      final conversationMap = {
        'messages': conversation.messages.map((final m) => m.toJson()).toList(),
        'events': conversation.events.map((final e) => e.toJson()).toList(),
        'createdAt': conversation.createdAt.toIso8601String(),
        'lastUpdatedAt': conversation.lastUpdatedAt.toIso8601String(),
      };

      // 2. Usar el repositorio para exportar a JSON string
      return await _repository.exportAllToJson(conversationMap);
    } on Exception catch (error) {
      throw Exception('Failed to export chat: $error');
    }
  }
}
