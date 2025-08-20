import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';

/// Adaptador que convierte IAIService a IVoiceAiService
class VoiceAiAdapter implements IVoiceAiService {
  final IAIService _aiService;

  const VoiceAiAdapter(this._aiService);

  @override
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? options,
  }) async {
    // Construir mensajes en el formato esperado por IAIService
    final messages = <Map<String, dynamic>>[];

    // Agregar historial si existe
    if (conversationHistory != null) {
      for (final historyMessage in conversationHistory) {
        messages.add({
          'role': historyMessage['role'] ?? 'user',
          'content': historyMessage['content'] ?? '',
        });
      }
    }

    // Agregar mensaje actual
    messages.add({'role': 'user', 'content': message});

    // Enviar al servicio de IA
    final response = await _aiService.sendMessage(
      messages: messages,
      options: options,
    );

    // Extraer el texto de la respuesta
    return (response['text'] ?? response['response'] ?? '')?.toString() ?? '';
  }

  @override
  bool get isAvailable => true;

  @override
  Future<List<String>> getAvailableModels() async {
    return await _aiService.getAvailableModels();
  }
}
