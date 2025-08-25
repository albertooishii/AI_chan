import 'package:ai_chan/chat/domain/models.dart';
import 'package:ai_chan/chat/domain/interfaces.dart';
import 'package:ai_chan/chat/domain/services.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/image_request_service.dart';

/// Send Message Use Case - Chat Application Layer
/// Orquesta el proceso completo de envío de mensaje incluyendo:
/// - Validación del mensaje
/// - Adición a la conversación
/// - Procesamiento de respuesta de IA
/// - Actualización de estado
class SendMessageUseCase {
  final IChatRepository _repository;
  final IChatResponseService _responseService;

  SendMessageUseCase({required IChatRepository repository, required IChatResponseService responseService})
    : _repository = repository,
      _responseService = responseService;

  /// Ejecuta el caso de uso de envío de mensaje
  Future<ChatConversation> execute({
    required ChatConversation currentConversation,
    required Message userMessage,
  }) async {
    // 1. Validar mensaje del usuario
    if (!ChatValidationService.isValidMessage(userMessage)) {
      throw ArgumentError('Invalid message: ${userMessage.text}');
    }

    // 2. Marcar mensaje como enviado y añadir a la conversación
    final sentMessage = userMessage.copyWith(status: MessageStatus.sent);
    var updatedConversation = currentConversation.addMessage(sentMessage);

    // 3. Preparar mensajes para la IA (convertir a formato Map)
    final messagesForAI = updatedConversation.messages.map((msg) => _messageToMap(msg)).toList();

    try {
      // 4. Detectar si el usuario pidió explícitamente una foto y forzar generación
      final wantsImage = ImageRequestService.isImageRequested(
        text: userMessage.text,
        history: updatedConversation.messages,
      );
      // Pasar la opción enableImageGeneration al servicio de respuesta
      final aiResponse = await _responseService.sendChat(messagesForAI, options: {'enableImageGeneration': wantsImage});

      // 5. Crear mensaje del asistente basado en la respuesta
      final assistantMessage = Message(
        text: aiResponse['text'] ?? '',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        status: MessageStatus.read,
        isImage: aiResponse['isImage'] ?? false,
        // Agregar otros campos según sea necesario
      );

      // 6. Añadir mensaje del asistente a la conversación
      updatedConversation = updatedConversation.addMessage(assistantMessage);

      // 7. Persistir conversación actualizada
      await _repository.saveAll(_conversationToMap(updatedConversation));

      // 8. Marcar mensaje del usuario como leído
      final finalConversation = updatedConversation.updateMessageStatus(
        updatedConversation.messages.length - 2, // Usuario message index
        MessageStatus.read,
      );

      return finalConversation;
    } catch (error) {
      // En caso de error, marcar mensaje del usuario como fallido
      updatedConversation.updateMessageStatus(
        updatedConversation.messages.length - 1, // Último mensaje (usuario)
        MessageStatus.failed,
      );

      rethrow; // Re-lanzar el error para que la UI lo maneje
    }
  }

  /// Convierte un Message a Map para compatibilidad con IChatResponseService
  Map<String, dynamic> _messageToMap(Message message) {
    return {
      'text': message.text,
      'sender': message.sender.name,
      'dateTime': message.dateTime.toIso8601String(),
      'isImage': message.isImage,
      if (message.image != null) 'image': message.image!.toJson(),
      'isAudio': message.isAudio,
      if (message.audioPath != null) 'audioPath': message.audioPath,
    };
  }

  /// Convierte una ChatConversation a Map para persistencia
  Map<String, dynamic> _conversationToMap(ChatConversation conversation) {
    return {
      'messages': conversation.messages.map((m) => m.toJson()).toList(),
      'events': conversation.events.map((e) => e.toJson()).toList(),
      'createdAt': conversation.createdAt.toIso8601String(),
      'lastUpdatedAt': conversation.lastUpdatedAt.toIso8601String(),
    };
  }
}
