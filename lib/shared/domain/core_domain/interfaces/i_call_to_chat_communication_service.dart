/// 🎯 **Call to Chat Communication Interface** - Bounded Context Abstraction
///
/// Defines the contract for communication between the call bounded context
/// and the chat bounded context. This interface enables loose coupling and
/// maintains bounded context isolation.
///
/// **Purpose:**
/// - Abstract chat operations needed by call context
/// - Enable dependency inversion between bounded contexts
/// - Maintain clean architecture principles
///
/// **DDD Principles:**
/// - ✅ Interface Segregation (only chat operations needed by calls)
/// - ✅ Dependency Inversion (call context depends on abstraction)
/// - ✅ Bounded Context Isolation (no direct coupling)
abstract class ICallToChatCommunicationService {
  /// Send a message to the chat system
  ///
  /// [text] The message text to send
  /// [model] Optional AI model to use
  /// Returns Future that completes when message is sent
  Future<void> sendMessage({required final String text, final String? model});

  /// Send a call-related message with additional metadata
  ///
  /// [text] The message text
  /// [callId] Optional call identifier for tracking
  /// [callType] Type of call (incoming, outgoing, etc.)
  /// [callDuration] Duration of the call if applicable
  Future<void> sendCallMessage({
    required final String text,
    final String? callId,
    final String? callType,
    final Duration? callDuration,
  });
}
