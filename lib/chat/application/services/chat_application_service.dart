import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_prompt_builder_service.dart';

/// Application Service que maneja la lógica de negocio del chat.
/// Orquesta casos de uso y servicios de dominio.
class ChatApplicationService {
  final IChatRepository _repository;
  final IPromptBuilderService _promptBuilder;

  ChatApplicationService({required IChatRepository repository, required IPromptBuilderService promptBuilder})
    : _repository = repository,
      _promptBuilder = promptBuilder;

  /// Construye el SystemPrompt JSON para chat escrito
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  }) => _promptBuilder.buildRealtimeSystemPromptJson(profile: profile, messages: messages, maxRecent: maxRecent);

  /// Construye el SystemPrompt JSON para llamadas de voz
  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  }) => _promptBuilder.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  /// Guarda el estado completo del chat
  Future<void> saveAll(Map<String, dynamic> exportedJson) async {
    await _repository.saveAll(exportedJson);
  }

  /// Carga el estado completo del chat
  Future<Map<String, dynamic>?> loadAll() async {
    return await _repository.loadAll();
  }

  /// Elimina todos los datos del chat
  Future<void> clearAll() async {
    await _repository.clearAll();
  }

  /// Exporta el chat a JSON
  Future<String> exportAllToJson(Map<String, dynamic> exportedJson) async {
    return await _repository.exportAllToJson(exportedJson);
  }

  /// Importa el chat desde JSON
  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async {
    return await _repository.importAllFromJson(jsonStr);
  }
}
