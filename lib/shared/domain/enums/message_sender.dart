/// Remitente de mensaje - Enum compartido entre contexts
enum MessageSender { user, assistant, system }

/// Extensión para MessageSender
extension MessageSenderExtension on MessageSender {
  String get name {
    switch (this) {
      case MessageSender.user:
        return 'user';
      case MessageSender.assistant:
        return 'assistant';
      case MessageSender.system:
        return 'system';
    }
  }

  static MessageSender fromString(final String value) {
    switch (value.toLowerCase()) {
      case 'user':
        return MessageSender.user;
      case 'assistant':
        return MessageSender.assistant;
      case 'system':
        return MessageSender.system;
      default:
        return MessageSender.user;
    }
  }

  /// Convierte a bool para compatibilidad (user = true, assistant/system = false)
  bool get isUser => this == MessageSender.user;

  /// Convierte a bool para compatibilidad (assistant = true, user/system = false)
  bool get isAssistant => this == MessageSender.assistant;

  /// Convierte a bool para compatibilidad (system = true, user/assistant = false)
  bool get isSystem => this == MessageSender.system;
}
