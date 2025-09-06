import 'package:ai_chan/chat/domain/models.dart';
import 'package:ai_chan/chat/domain/interfaces.dart';

/// Load Chat History Use Case - Chat Application Layer
/// Maneja la carga del historial de conversación desde el almacenamiento
class LoadChatHistoryUseCase {
  LoadChatHistoryUseCase({required final IChatRepository repository})
    : _repository = repository;
  final IChatRepository _repository;

  /// Ejecuta el caso de uso de carga de historial
  Future<ChatConversation> execute() async {
    try {
      // 1. Intentar cargar desde el repositorio
      final data = await _repository.loadAll();

      if (data != null) {
        // 2. Convertir datos cargados a ChatConversation
        return ChatConversation.fromJson(data);
      } else {
        // 3. Si no hay datos, devolver conversación vacía
        return ChatConversation.empty();
      }
    } on Exception catch (_) {
      // 4. En caso de error, devolver conversación vacía como fallback
      // Log del error podría agregarse aquí
      return ChatConversation.empty();
    }
  }
}
