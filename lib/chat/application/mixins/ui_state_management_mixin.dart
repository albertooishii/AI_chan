import 'package:flutter/material.dart';

/// 🎯 **UI State Management Mixin** - DDD Controller Optimization
///
/// Reduces boilerplate in controllers by automating common patterns:
/// - Loading state management
/// - Error handling with notifications
/// - Success operations with notifications
///
/// **Usage Pattern Before:**
/// ```dart
/// Future<void> someMethod() async {
///   _setLoading(true);
///   try {
///     await _service.someOperation();
///     _clearError();
///     notifyListeners();
///   } catch (e) {
///     _setError('Error message: $e');
///   } finally {
///     _setLoading(false);
///   }
/// }
/// ```
///
/// **Usage Pattern After:**
/// ```dart
/// Future<void> someMethod() async {
///   await executeWithState(
///     operation: () => _service.someOperation(),
///     errorMessage: 'Error message',
///   );
/// }
/// ```
mixin UIStateManagementMixin on ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  // Getters for UI state
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Executes an operation with full state management (loading + error + notifications)
  Future<T?> executeWithState<T>({
    required final Future<T> Function() operation,
    required final String errorMessage,
    final bool showLoading = true,
  }) async {
    if (showLoading) _setLoading(true);

    try {
      final result = await operation();
      _clearError();
      notifyListeners();
      return result;
    } on Exception catch (e) {
      _setError('$errorMessage: $e');
      return null;
    } finally {
      if (showLoading) _setLoading(false);
    }
  }

  /// Executes a void operation with notifications only (no loading state)
  Future<void> executeWithNotification({
    required final Future<void> Function() operation,
    required final String errorMessage,
  }) async {
    try {
      await operation();
      notifyListeners();
    } on Exception catch (e) {
      _setError('$errorMessage: $e');
    }
  }

  /// Executes a synchronous operation with notifications
  void executeSyncWithNotification({
    required final void Function() operation,
    final String? errorMessage,
  }) {
    try {
      operation();
      notifyListeners();
    } on Exception catch (e) {
      if (errorMessage != null) {
        _setError('$errorMessage: $e');
      }
    }
  }

  /// Simple delegate pattern: call service method and notify
  Future<void> delegate({
    required final Future<void> Function() serviceCall,
    final String? errorMessage,
  }) async {
    try {
      await serviceCall();
      notifyListeners();
    } on Exception catch (e) {
      if (errorMessage != null) {
        _setError('$errorMessage: $e');
      }
    }
  }

  // Private state management methods
  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
