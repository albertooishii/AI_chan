import 'package:ai_chan/chat/domain/interfaces/i_chat_logging_utils_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Basic implementation of IChatLoggingUtilsService for dependency injection
class BasicChatLoggingUtilsService implements IChatLoggingUtilsService {
  @override
  void logInfo(final String message, [final String? tag]) {
    Log.i(message, tag: tag ?? 'CHAT_SERVICE');
  }

  @override
  void logWarning(final String message, [final String? tag]) {
    Log.w(message, tag: tag ?? 'CHAT_SERVICE');
  }

  @override
  void logError(
    final String message, [
    final String? tag,
    final Object? error,
  ]) {
    if (error != null) {
      Log.e(message, tag: tag ?? 'CHAT_SERVICE', error: error);
    } else {
      Log.e(message, tag: tag ?? 'CHAT_SERVICE');
    }
  }

  @override
  void logDebug(final String message, [final String? tag]) {
    Log.d(message, tag: tag ?? 'CHAT_SERVICE');
  }

  @override
  void logErrorWithStack(
    final String message,
    final String stackTrace, [
    final String? tag,
  ]) {
    Log.e('$message\n$stackTrace', tag: tag ?? 'CHAT_SERVICE');
  }
}
