import 'package:ai_chan/chat/domain/interfaces/i_chat_logger.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Implementation of IChatLogger that delegates to shared logging utility
/// This adapter allows chat context to use logging while maintaining isolation
class ChatLoggerAdapter implements IChatLogger {
  @override
  void debug(final String message, {final String? tag}) {
    Log.d(message, tag: tag ?? 'CHAT');
  }

  @override
  void error(final String message, {final String? tag, final Object? error}) {
    Log.e(message, tag: tag ?? 'CHAT', error: error);
  }
}
