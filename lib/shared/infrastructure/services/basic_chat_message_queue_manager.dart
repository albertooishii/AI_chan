import 'package:ai_chan/chat/domain/interfaces/i_chat_message_queue_manager.dart';

/// Basic implementation of IChatMessageQueueManager for dependency injection
class BasicChatMessageQueueManager implements IChatMessageQueueManager {
  @override
  int get queuedCount => 0;

  @override
  void enqueue(final String messageId, {final dynamic options}) {
    // Basic implementation - do nothing
  }

  @override
  void cancelTimer() {
    // Basic implementation - do nothing
  }

  @override
  void ensureTimer() {
    // Basic implementation - do nothing
  }

  @override
  void flushNow() {
    // Basic implementation - do nothing
  }

  @override
  void dispose() {
    // Basic implementation - do nothing
  }
}
