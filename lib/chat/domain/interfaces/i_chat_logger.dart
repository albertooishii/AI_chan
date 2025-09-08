/// Interface for logging within the chat bounded context
/// This abstracts external logging dependencies to maintain context isolation
abstract class IChatLogger {
  /// Log debug message
  void debug(final String message, {final String? tag});

  /// Log error message
  void error(final String message, {final String? tag, final Object? error});
}
