import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/models/chat_conversation.dart';

/// Chat Validation Service - Domain Service
/// Proporciona validaciones de negocio específicas del dominio de chat
class ChatValidationService {
  /// Valida que un mensaje sea válido para envío
  static bool isValidMessage(Message message) {
    // Un mensaje válido debe tener texto o ser una imagen
    if (message.text.trim().isEmpty && !message.isImage) {
      return false;
    }

    // Si es una imagen, debe tener datos de imagen válidos
    if (message.isImage && message.image == null) {
      return false;
    }

    // Mensajes de audio deben tener ruta de audio válida
    if (message.isAudio && (message.audioPath?.trim().isEmpty ?? true)) {
      return false;
    }

    return true;
  }

  /// Valida que un evento de chat sea válido
  static bool isValidChatEvent(ChatEvent event) {
    // Un evento debe tener tipo y descripción no vacíos
    if (event.type.trim().isEmpty || event.description.trim().isEmpty) {
      return false;
    }

    return true;
  }

  /// Valida que una conversación esté en estado consistente
  static bool isValidConversation(ChatConversation conversation) {
    // Verificar que no hay mensajes inválidos
    for (final message in conversation.messages) {
      if (!isValidMessage(message)) {
        return false;
      }
    }

    // Verificar que no hay eventos inválidos
    for (final event in conversation.events) {
      if (!isValidChatEvent(event)) {
        return false;
      }
    }

    // Verificar fechas consistentes
    if (conversation.lastUpdatedAt.isBefore(conversation.createdAt)) {
      return false;
    }

    return true;
  }

  /// Valida que el texto del mensaje no exceda límites
  static bool isWithinTextLimits(String text, {int maxLength = 10000}) {
    return text.length <= maxLength;
  }

  /// Valida que el sender del mensaje sea válido
  static bool isValidSender(MessageSender sender) {
    return MessageSender.values.contains(sender);
  }

  /// Valida que el estado del mensaje sea válido
  static bool isValidStatus(MessageStatus status) {
    return MessageStatus.values.contains(status);
  }
}
