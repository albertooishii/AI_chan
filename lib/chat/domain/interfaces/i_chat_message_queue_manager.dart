/// 🎯 **Chat Message Queue Manager Interface** - Domain Abstraction for Message Queue Management
///
/// Defines the contract for message queue management within the chat bounded context.
/// This ensures bounded context isolation while providing message queuing functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
library;

import 'package:ai_chan/chat/domain/models/chat_queued_send_options.dart';

abstract class IChatMessageQueueManager {
  /// Gets the count of queued messages
  int get queuedCount;

  /// Enqueues a message with options
  void enqueue(final String messageId, {final ChatQueuedSendOptions? options});

  /// Cancels the timer
  void cancelTimer();

  /// Ensures timer is running
  void ensureTimer();

  /// Forces immediate flush of queued messages
  void flushNow();

  /// Disposes of queue manager resources
  void dispose();
}
