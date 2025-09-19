import 'package:flutter/material.dart';
import 'package:ai_chan/shared/domain/interfaces/i_navigation_service.dart';
// REMOVED: Direct screen imports to fix Clean Architecture violation
// Screens should be provided via dependency injection or route factories

/// Implementation of navigation service that handles cross-context navigation
/// NOTE: This service centralizes cross-context navigation to avoid
/// direct imports in presentation layers of bounded contexts
class NavigationService implements INavigationService {
  NavigationService(this._navigatorKey);
  final GlobalKey<NavigatorState> _navigatorKey;

  NavigatorState? get _navigator => _navigatorKey.currentState;

  @override
  Future<void> navigateToVoice() async {
    if (_navigator != null) {
      // Use named route to avoid direct screen dependency
      await _navigator!.pushNamed('/voice');
    }
  }

  @override
  Future<void> navigateToChat() async {
    if (_navigator != null) {
      // Chat navigation requires parameters - to be implemented when needed
      throw UnimplementedError('Chat navigation requires specific parameters');
    }
  }

  @override
  Future<void> navigateToOnboarding() async {
    if (_navigator != null) {
      // Onboarding navigation requires parameters - to be implemented when needed
      throw UnimplementedError(
        'Onboarding navigation requires specific parameters',
      );
    }
  }

  @override
  void goBack() {
    if (_navigator != null && _navigator!.canPop()) {
      _navigator!.pop();
    }
  }

  @override
  bool canGoBack() {
    return _navigator?.canPop() ?? false;
  }
}
