import 'package:ai_chan/chat/domain/interfaces/i_logging_service.dart';
import 'package:flutter/foundation.dart';

/// Basic implementation of ILoggingService for dependency injection
class BasicLoggingService implements ILoggingService {
  @override
  void debug(final String message, {final String? tag, final Object? error}) {
    debugPrint(
      '[DEBUG${tag != null ? ' $tag' : ''}] $message${error != null ? ' | Error: $error' : ''}',
    );
  }

  @override
  void info(final String message, {final String? tag, final Object? error}) {
    debugPrint(
      '[INFO${tag != null ? ' $tag' : ''}] $message${error != null ? ' | Error: $error' : ''}',
    );
  }

  @override
  void warning(final String message, {final String? tag, final Object? error}) {
    debugPrint(
      '[WARN${tag != null ? ' $tag' : ''}] $message${error != null ? ' | Error: $error' : ''}',
    );
  }

  @override
  void error(
    final String message, {
    final String? tag,
    final Object? error,
    final StackTrace? stackTrace,
  }) {
    debugPrint(
      '[ERROR${tag != null ? ' $tag' : ''}] $message${error != null ? ' | Error: $error' : ''}',
    );
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }
}
