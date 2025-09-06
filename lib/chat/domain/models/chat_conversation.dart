import 'package:ai_chan/core/models.dart';

/// Chat Conversation - Domain Aggregate
/// Representa una conversación de chat completa con sus mensajes y eventos
class ChatConversation {
  ChatConversation({
    required this.messages,
    required this.events,
    required this.createdAt,
    required this.lastUpdatedAt,
  });

  /// Crea una nueva conversación vacía
  factory ChatConversation.empty() {
    final now = DateTime.now();
    return ChatConversation(
      messages: [],
      events: [],
      createdAt: now,
      lastUpdatedAt: now,
    );
  }

  /// Deserialización desde persistencia
  factory ChatConversation.fromJson(final Map<String, dynamic> json) {
    final messagesList = (json['messages'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Message.fromJson)
        .toList();

    final eventsList = (json['events'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(ChatEvent.fromJson)
        .toList();

    return ChatConversation(
      messages: messagesList,
      events: eventsList,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      lastUpdatedAt:
          DateTime.tryParse(json['lastUpdatedAt'] ?? '') ?? DateTime.now(),
    );
  }
  final List<Message> messages;
  final List<ChatEvent> events;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;

  /// Añade un mensaje a la conversación
  ChatConversation addMessage(final Message message) {
    final updatedMessages = List<Message>.from(messages)..add(message);
    return ChatConversation(
      messages: updatedMessages,
      events: events,
      createdAt: createdAt,
      lastUpdatedAt: DateTime.now(),
    );
  }

  /// Añade un evento a la conversación
  ChatConversation addEvent(final ChatEvent event) {
    final updatedEvents = List<ChatEvent>.from(events)..add(event);
    return ChatConversation(
      messages: messages,
      events: updatedEvents,
      createdAt: createdAt,
      lastUpdatedAt: DateTime.now(),
    );
  }

  /// Actualiza el estado de un mensaje específico
  ChatConversation updateMessageStatus(
    final int messageIndex,
    final MessageStatus newStatus,
  ) {
    if (messageIndex < 0 || messageIndex >= messages.length) {
      return this; // No cambios si el índice es inválido
    }

    final updatedMessages = List<Message>.from(messages);
    updatedMessages[messageIndex] = updatedMessages[messageIndex].copyWith(
      status: newStatus,
    );

    return ChatConversation(
      messages: updatedMessages,
      events: events,
      createdAt: createdAt,
      lastUpdatedAt: DateTime.now(),
    );
  }

  /// Obtiene los mensajes más recientes limitados por cantidad
  List<Message> getRecentMessages(final int limit) {
    if (messages.length <= limit) return List.unmodifiable(messages);
    return List.unmodifiable(messages.sublist(messages.length - limit));
  }

  /// Obtiene solo los mensajes que no son del sistema
  List<Message> get userAndAssistantMessages {
    return messages
        .where((final msg) => msg.sender != MessageSender.system)
        .toList();
  }

  /// Obtiene la cantidad total de mensajes
  int get messageCount => messages.length;

  /// Obtiene la cantidad total de eventos
  int get eventCount => events.length;

  /// Verifica si la conversación está vacía
  bool get isEmpty => messages.isEmpty && events.isEmpty;

  /// Obtiene el último mensaje
  Message? get lastMessage {
    return messages.isEmpty ? null : messages.last;
  }

  /// Serialización para persistencia
  Map<String, dynamic> toJson() => {
    'messages': messages.map((final m) => m.toJson()).toList(),
    'events': events.map((final e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  };
}
