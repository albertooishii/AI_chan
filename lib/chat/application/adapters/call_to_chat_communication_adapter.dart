import 'package:ai_chan/core/domain/interfaces/i_call_to_chat_communication_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';

/// 🎯 **Call to Chat Communication Adapter** - Bounded Context Bridge
///
/// Adapter that implements the communication interface between call and chat
/// bounded contexts. This maintains isolation while enabling necessary
/// cross-context communication.
///
/// **Clean Architecture Compliance:**
/// ✅ Implements domain interface (ICallToChatCommunicationService)
/// ✅ Application layer - coordinates domain logic
/// ✅ Depends on abstractions, not concretions
/// ✅ Enables bounded context communication without tight coupling
class CallToChatCommunicationAdapter
    implements ICallToChatCommunicationService {
  const CallToChatCommunicationAdapter(this._chatController);

  final IChatController _chatController;

  @override
  Future<void> sendMessage({
    required final String text,
    final String? model,
  }) async {
    await _chatController.sendMessage(
      text: text,
    ); // Model selection is now automatic
  }

  @override
  Future<void> sendCallMessage({
    required final String text,
    final String? callId,
    final String? callType,
    final Duration? callDuration,
  }) async {
    // Add call-specific metadata to the message if needed
    final enhancedText = _enhanceMessageWithCallMetadata(
      text: text,
      callId: callId,
      callType: callType,
      callDuration: callDuration,
    );

    await _chatController.sendMessage(text: enhancedText);
  }

  String _enhanceMessageWithCallMetadata({
    required final String text,
    final String? callId,
    final String? callType,
    final Duration? callDuration,
  }) {
    // For now, just return the text as-is
    // In the future, this could add metadata like:
    // "[Call $callId] $text" or include duration information
    return text;
  }
}
