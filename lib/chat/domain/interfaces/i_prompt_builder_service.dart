import 'package:ai_chan/core/models.dart';

/// Interface del dominio para la construcción de prompts del sistema.
/// Define las reglas de negocio para cómo debe comportarse la IA.
abstract class IPromptBuilderService {
  /// Construye el SystemPrompt JSON principal usado en chat escrito.
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  });

  /// Construye el SystemPrompt JSON para llamadas de voz.
  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  });

  /// Obtiene las instrucciones para generación de imágenes.
  Map<String, dynamic> getImageInstructions(String userName);

  /// Obtiene los metadatos para procesamiento de imágenes.
  Map<String, dynamic> getImageMetadata(String userName);
}
