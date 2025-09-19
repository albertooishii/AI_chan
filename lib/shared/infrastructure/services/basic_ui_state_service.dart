/// Basic listener for UI state changes
abstract class BasicUIStateListener {
  void onLoadingChanged(final bool isLoading);
  void onErrorChanged(final String? errorMessage);
  void onOperationSuccess(final String? message);
}

/// 🎯 **Basic UI State Service** - Infrastructure Implementation
///
/// Basic implementation of UI state management for Clean Architecture compliance.
/// This implementation doesn't depend on Flutter and can be used in application layer.
///
/// **Clean Architecture Compliance:**
/// ✅ Infrastructure implements domain interfaces
/// ✅ No Flutter dependencies in application layer
/// ✅ Platform-agnostic state management
class BasicUIStateService {
  bool _isLoading = false;
  String? _errorMessage;
  final List<BasicUIStateListener> _listeners = [];

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  Future<T?> executeWithState<T>({
    required final Future<T> Function() operation,
    required final String errorMessage,
    final bool showLoading = true,
  }) async {
    if (showLoading) setLoading(true);

    try {
      final result = await operation();
      clearError();
      return result;
    } on Exception catch (e) {
      setError('$errorMessage: ${e.toString()}');
      return null;
    } finally {
      if (showLoading) setLoading(false);
    }
  }

  void setLoading(final bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      _notifyLoadingChanged();
    }
  }

  void setError(final String? message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      _notifyErrorChanged();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _notifyErrorChanged();
    }
  }

  void notifyListeners() {
    // This is a no-op in the basic implementation
    // In a real implementation, this would notify registered listeners
  }

  void addListener(final BasicUIStateListener listener) {
    _listeners.add(listener);
  }

  void removeListener(final BasicUIStateListener listener) {
    _listeners.remove(listener);
  }

  void _notifyLoadingChanged() {
    for (final listener in _listeners) {
      listener.onLoadingChanged(_isLoading);
    }
  }

  void _notifyErrorChanged() {
    for (final listener in _listeners) {
      listener.onErrorChanged(_errorMessage);
    }
  }
}
