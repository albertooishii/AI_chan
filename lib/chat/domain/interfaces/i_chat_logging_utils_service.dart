/// 🎯 **Chat Logging Utils Service Interface** - Domain Abstraction for Logging Operations
///
/// Defines the contract for logging utility operations within the chat bounded context.
/// This ensures bounded context isolation while providing logging functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatLoggingUtilsService {
  /// Logs an info message
  void logInfo(final String message, [final String? tag]);

  /// Logs a warning message
  void logWarning(final String message, [final String? tag]);

  /// Logs an error message
  void logError(final String message, [final String? tag, final Object? error]);

  /// Logs a debug message
  void logDebug(final String message, [final String? tag]);

  /// Logs an error with stack trace
  void logErrorWithStack(
    final String message,
    final String stackTrace, [
    final String? tag,
  ]);
}
