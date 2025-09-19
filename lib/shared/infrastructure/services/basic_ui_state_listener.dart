import 'package:ai_chan/shared/domain/interfaces/i_ui_state_service.dart';

/// 🎯 **Basic UI State Listener** - Infrastructure Implementation
///
/// Basic implementation of IUIStateListener for Clean Architecture compliance.
/// This implementation can be used for testing or as a base class for UI components.
///
/// **Clean Architecture Compliance:**
/// ✅ Infrastructure implements domain interfaces
/// ✅ Provides basic listener functionality
/// ✅ Can be extended by UI components
class BasicUIStateListener implements IUIStateListener {
  @override
  void onLoadingChanged(final bool isLoading) {
    // Basic implementation - can be overridden by UI components
  }

  @override
  void onErrorChanged(final String? errorMessage) {
    // Basic implementation - can be overridden by UI components
  }

  @override
  void onOperationSuccess(final String? message) {
    // Basic implementation - can be overridden by UI components
  }
}
