// Shared Domain Interfaces for Cross-Context Communication
//
// This file contains interfaces that allow bounded contexts to communicate
// without creating direct dependencies between them.

/// Interface for chat integration services
/// Allows call context to communicate with chat without direct dependency
abstract class IChatIntegrationService {
  /// Send a message from call context to chat
  Future<void> sendMessageFromCall(
    final String message,
    final Map<String, dynamic>? metadata,
  );

  /// Get chat status for call integration
  Future<bool> isChatAvailable();

  /// Notify chat about call events
  Future<void> notifyCallEvent(
    final String eventType,
    final Map<String, dynamic> data,
  );
}

/// Interface for call integration services
/// Allows chat context to communicate with call without direct dependency
abstract class ICallIntegrationService {
  /// Start a call from chat context
  Future<void> startCallFromChat();

  /// End current call
  Future<void> endCallFromChat();

  /// Check if call is active
  Future<bool> isCallActive();

  /// Send message to call context
  Future<void> sendMessageToCall(final String message);
}

/// Interface for TTS services that can be used across contexts
abstract class ITextToSpeechService {
  Future<void> speak(
    final String text, {
    final String? language,
    final double? rate,
    final double? pitch,
  });
  Future<void> stop();
  Future<bool> isSpeaking();
}

/// Interface for STT services that can be used across contexts
abstract class ISpeechToTextService {
  Future<void> startListening({final String? language});
  Future<void> stopListening();
  Stream<String> get onTextReceived;
  Future<bool> isAvailable();
}

/// Shared DTOs for cross-context communication
class CallToChatMessage {
  CallToChatMessage({
    required this.content,
    required this.timestamp,
    this.metadata,
  });
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
}

class ChatToCallMessage {
  ChatToCallMessage({
    required this.content,
    required this.timestamp,
    required this.messageType,
  });
  final String content;
  final DateTime timestamp;
  final String messageType;

  Map<String, dynamic> toJson() => {
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'messageType': messageType,
  };
}
