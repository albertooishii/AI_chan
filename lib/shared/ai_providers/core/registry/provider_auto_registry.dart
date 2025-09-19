/// Auto-discovery and dynamic registration system for AI Providers.
/// This system eliminates hardcoding by allowing providers to self-register.
library;

import 'package:ai_chan/shared.dart';

/// Signature for provider constructor functions
typedef ProviderConstructor = IAIProvider Function(ProviderConfig config);

/// Exception thrown when provider registration fails
class ProviderRegistrationException implements Exception {
  const ProviderRegistrationException(this.message, [this.cause]);

  final String message;
  final dynamic cause;

  @override
  String toString() =>
      'ProviderRegistrationException: $message${cause != null ? ' (Caused by: $cause)' : ''}';
}

/// Dynamic registry for AI Provider constructors.
/// This eliminates the need for hardcoded switch statements.
class ProviderAutoRegistry {
  static final Map<String, ProviderConstructor> _constructors = {};
  static final Map<String, Map<String, List<String>>> _modelPrefixes = {};
  static bool _initialized = false;

  /// Register a provider constructor with the system
  static void registerConstructor(
    String providerId,
    final ProviderConstructor constructor, {
    final List<String>? modelPrefixes,
  }) {
    providerId = providerId.toLowerCase().trim();

    if (_constructors.containsKey(providerId)) {
      Log.w(
        '[ProviderAutoRegistry] Overriding existing constructor for: $providerId',
      );
    }

    _constructors[providerId] = constructor;

    if (modelPrefixes != null && modelPrefixes.isNotEmpty) {
      _modelPrefixes[providerId] = {'prefixes': modelPrefixes};
    }

    Log.i('[ProviderAutoRegistry] ✅ Registered constructor: $providerId');
  }

  /// Create a provider instance using registered constructors
  static IAIProvider? createProvider(
    String providerId,
    final ProviderConfig config,
  ) {
    providerId = providerId.toLowerCase().trim();

    final constructor = _constructors[providerId];
    if (constructor == null) {
      Log.w('[ProviderAutoRegistry] ❌ No constructor found for: $providerId');
      return null;
    }

    try {
      final provider = constructor(config);
      Log.i('[ProviderAutoRegistry] ✅ Created provider: $providerId');
      return provider;
    } catch (e) {
      Log.e(
        '[ProviderAutoRegistry] ❌ Failed to create provider $providerId: $e',
      );
      throw ProviderRegistrationException(
        'Failed to create provider: $providerId',
        e,
      );
    }
  }

  /// Get provider for model based on registered prefixes
  static String? getProviderForModel(final String modelId) {
    final normalized = modelId.trim().toLowerCase();

    for (final entry in _modelPrefixes.entries) {
      final providerId = entry.key;
      final prefixes = entry.value['prefixes'];

      if (prefixes != null) {
        for (final prefix in prefixes) {
          if (normalized.startsWith(prefix.toLowerCase())) {
            return providerId;
          }
        }
      }
    }

    return null;
  }

  /// Check if a provider type is registered
  static bool isProviderRegistered(final String providerId) {
    return _constructors.containsKey(providerId.toLowerCase().trim());
  }

  /// Get all registered provider IDs
  static List<String> getRegisteredProviders() {
    return _constructors.keys.toList();
  }

  /// Get model prefixes for a provider
  static List<String>? getModelPrefixes(final String providerId) {
    final prefixes = _modelPrefixes[providerId.toLowerCase().trim()];
    return prefixes?['prefixes'];
  }

  /// Initialize with all known providers
  static void initializeKnownProviders() {
    if (_initialized) {
      Log.w('[ProviderAutoRegistry] Already initialized, skipping...');
      return;
    }

    Log.i('[ProviderAutoRegistry] Initializing known providers...');

    // Register all known providers directly (simplified approach)
    _registerKnownProviders();

    _initialized = true;
    Log.i(
      '[ProviderAutoRegistry] ✅ Initialization complete: ${_constructors.length} providers registered',
    );
  }

  /// Register all known providers (replaces hardcoded imports)
  static void _registerKnownProviders() {
    // For now, this is a placeholder since the providers will be registered
    // via provider_registration.dart. This method exists for future
    // auto-discovery features.

    Log.i('[ProviderAutoRegistry] Ready for provider registration...');
  }

  /// Clear all registrations (useful for testing)
  static void clear() {
    _constructors.clear();
    _modelPrefixes.clear();
    _initialized = false;
    Log.i('[ProviderAutoRegistry] Registry cleared');
  }

  /// Get registry statistics
  static Map<String, dynamic> getStats() {
    return {
      'registered_providers': _constructors.length,
      'providers': _constructors.keys.toList(),
      'model_prefixes': Map.from(_modelPrefixes),
      'initialized': _initialized,
    };
  }
}
