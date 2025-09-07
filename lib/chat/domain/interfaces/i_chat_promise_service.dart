/// 🎯 **Chat Promise Service Interface** - Domain Abstraction for Async Operations
///
/// Defines the contract for promise-based operations within the chat bounded context.
/// This ensures bounded context isolation while providing async operation management.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatPromiseService {
  /// Executes an operation with promise management
  Future<T> execute<T>(final Future<T> Function() operation);

  /// Executes multiple operations in parallel
  Future<List<T>> executeAll<T>(final List<Future<T> Function()> operations);

  /// Creates a promise that resolves after a delay
  Future<void> delay(final Duration duration);

  /// Creates a promise that resolves with a timeout
  Future<T> timeout<T>(
    final Future<T> Function() operation,
    final Duration timeout,
  );

  /// Restores promises from events
  void restoreFromEvents();

  /// Analyzes promises after IA message
  void analyzeAfterIaMessage(final List<dynamic> messages);

  /// Schedules a promise event
  void schedulePromiseEvent(final dynamic event);

  /// Disposes of promise resources
  void dispose();
}
