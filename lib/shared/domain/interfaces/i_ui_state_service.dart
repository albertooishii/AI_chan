/// 🎯 **UI State Service Interface** - Domain Abstraction for Clean Architecture
///
/// Defines the contract for UI state management without Flutter dependencies.
/// This allows the application layer to manage state while remaining platform-agnostic.
///
/// **Clean Architecture Compliance:**
/// ✅ Application layer depends only on domain interfaces
/// ✅ No direct Flutter framework dependencies
/// ✅ Platform-agnostic state management
abstract class IUIStateService {
  /// Whether an operation is currently in progress
  bool get isLoading;

  /// Current error message, null if no error
  String? get errorMessage;

  /// Executes an operation with full state management
  Future<T?> executeWithState<T>({
    required final Future<T> Function() operation,
    required final String errorMessage,
    final bool showLoading = true,
  });

  /// Sets loading state
  void setLoading(final bool loading);

  /// Sets error message
  void setError(final String? message);

  /// Clears current error
  void clearError();

  /// Notifies listeners of state changes
  void notifyListeners();
}

/// 🎯 **UI State Listener Interface** - Observer Pattern for State Changes
///
/// Defines the contract for components that need to react to UI state changes.
/// This enables loose coupling between state management and UI components.
abstract class IUIStateListener {
  /// Called when loading state changes
  void onLoadingChanged(final bool isLoading);

  /// Called when error state changes
  void onErrorChanged(final String? errorMessage);

  /// Called when operation completes successfully
  void onOperationSuccess(final String? message);
}
