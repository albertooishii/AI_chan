import 'package:ai_chan/chat/domain/models.dart';
import 'package:ai_chan/chat/domain/interfaces.dart';

/// Import Chat Use Case - Chat Application Layer
/// Maneja la importación de conversación desde JSON string
class ImportChatUseCase {
  final IChatRepository _repository;

  ImportChatUseCase({required IChatRepository repository})
    : _repository = repository;

  /// Ejecuta el caso de uso de importación
  Future<ChatConversation> execute(String jsonString) async {
    try {
      // 1. Usar el repositorio para parsear el JSON
      final data = await _repository.importAllFromJson(jsonString);

      if (data != null) {
        // 2. Convertir a ChatConversation
        final conversation = ChatConversation.fromJson(data);

        // 3. Guardar la conversación importada
        await _repository.saveAll(data);

        return conversation;
      } else {
        throw Exception('Invalid JSON format or empty data');
      }
    } catch (error) {
      throw Exception('Failed to import chat: $error');
    }
  }
}
