/// 🎯 **Chat Debounced Persistence Service Interface** - Domain Abstraction for Debounced Persistence
///
/// Defines the contract for debounced persistence operations within the chat bounded context.
/// This ensures bounded context isolation while providing optimized persistence functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatDebouncedPersistenceService {
  /// Triggers the debounced persistence operation
  void trigger();

  /// Disposes of the debounced persistence resources
  void dispose();
}
