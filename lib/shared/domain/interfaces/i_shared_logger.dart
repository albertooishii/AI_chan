/// Shared domain interface for logging operations.
/// Can be used across bounded contexts for logging functionality.
abstract class ISharedLogger {
  /// Logs debug messages
  void debug(final String message, {final String? tag});

  /// Logs error messages with optional error object
  void error(final String message, {final String? tag, final Object? error});
}
