import 'package:ai_chan/shared/domain/interfaces/i_ui_state_service.dart';

/// 🎯 **Basic UI State Service** - Infrastructure Implementation
///
/// Basic implementation of IUIStateService for Clean Architecture compliance.
/// This implementation doesn't depend on Flutter and can be used in application layer.
///
/// **Clean Architecture Compliance:**
/// ✅ Infrastructure implements domain interfaces
/// ✅ No Flutter dependencies in application layer
/// ✅ Platform-agnostic state management
class BasicUIStateService implements IUIStateService {
  bool _isLoading = false;
  String? _errorMessage;
  final List<IUIStateListener> _listeners = [];

  @override
  bool get isLoading => _isLoading;

  @override
  String? get errorMessage => _errorMessage;

  @override
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

  @override
  void setLoading(final bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      _notifyLoadingChanged();
    }
  }

  @override
  void setError(final String? message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      _notifyErrorChanged();
    }
  }

  @override
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _notifyErrorChanged();
    }
  }

  @override
  void notifyListeners() {
    // This is a no-op in the basic implementation
    // In a real implementation, this would notify registered listeners
  }

  void addListener(final IUIStateListener listener) {
    _listeners.add(listener);
  }

  void removeListener(final IUIStateListener listener) {
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
