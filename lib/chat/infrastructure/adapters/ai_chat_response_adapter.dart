import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/models.dart';
import 'ai_chat_response_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/services/ai_service.dart' show getAllAIModels;

/// Adaptador que implementa IChatResponseService delegando en AiChatResponseService.
/// Convierte el shape genérico de mensajes (Map) a objetos de dominio y devuelve
/// un Map sencillo con keys predecibles para el consumidor.
class AiChatResponseAdapter implements IChatResponseService {
  const AiChatResponseAdapter();

  @override
  Future<List<String>> getSupportedModels() async {
    return await getAllAIModels();
  }

  @override
  Future<Map<String, dynamic>> sendChat(
    List<Map<String, dynamic>> messages, {
    Map<String, dynamic>? options,
  }) async {
    // Esperamos que el primer message pueda contener systemPrompt en options
    try {
      // Extraer systemPrompt enviado en options (si existe) como SystemPrompt o Map
      final systemPromptObj =
          options != null && options['systemPromptObj'] is SystemPrompt
          ? options['systemPromptObj'] as SystemPrompt
          : (options != null && options['systemPromptObj'] is Map
                ? SystemPrompt.fromJson(
                    options['systemPromptObj'] as Map<String, dynamic>,
                  )
                : SystemPrompt.fromJson({
                    'profile': {},
                    'dateTime': DateTime.now().toIso8601String(),
                    'instructions': {},
                  }));

      final model = options != null && options['model'] is String
          ? options['model'] as String
          : '';
      final imageBase64 = options != null && options['imageBase64'] is String
          ? options['imageBase64'] as String
          : null;
      final imageMimeType =
          options != null && options['imageMimeType'] is String
          ? options['imageMimeType'] as String
          : null;
      final enableImageGeneration =
          options != null && options['enableImageGeneration'] is bool
          ? options['enableImageGeneration'] as bool
          : false;

      // Convertir messages (Map) -> List<Message>
      final recent = messages.map((m) {
        final role = (m['role'] as String?) ?? 'user';
        final content = (m['content'] as String?) ?? '';
        final dateTime = m['datetime'] != null
            ? DateTime.tryParse(m['datetime'] as String) ?? DateTime.now()
            : DateTime.now();
        final sender = role == 'user'
            ? MessageSender.user
            : (role == 'ia' ? MessageSender.assistant : MessageSender.system);
        return Message(
          text: content,
          sender: sender,
          dateTime: dateTime,
          status: MessageStatus.read,
        );
      }).toList();

      final aiResult = await AiChatResponseService.send(
        recentMessages: recent,
        systemPromptObj: systemPromptObj,
        model: model.isNotEmpty ? model : Config.requireDefaultTextModel(),
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );

      return {
        'text': aiResult.text,
        'isImage': aiResult.isImage,
        'imagePath': aiResult.imagePath,
        'prompt': aiResult.prompt,
        'seed': aiResult.seed,
        'finalModelUsed': aiResult.finalModelUsed,
      };
    } catch (e) {
      return {'text': 'error al conectar con la ia', 'isImage': false};
    }
  }
}
