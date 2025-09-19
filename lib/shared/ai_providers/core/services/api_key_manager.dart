/// Dynamic API Key Management System with automatic fallback.
/// Supports multiple API keys per provider with automatic rotation on failure.
library;

import 'package:ai_chan/shared.dart';

/// Represents the status of an API key
enum ApiKeyStatus {
  active, // Key is working normally
  failed, // Key failed recently, should not be used
  exhausted, // Key hit rate limits
  invalid, // Key is invalid/revoked
}

/// Information about an API key and its current status
class ApiKeyInfo {
  ApiKeyInfo({
    required this.key,
    required this.index,
    this.status = ApiKeyStatus.active,
    this.lastUsed,
    this.lastError,
    this.failureCount = 0,
  });

  final String key;
  final int index;
  ApiKeyStatus status;
  DateTime? lastUsed;
  String? lastError;
  int failureCount;

  /// Check if key is available for use
  bool get isAvailable => status == ApiKeyStatus.active;

  /// Mark key as failed with error details
  void markFailed(final String error) {
    status = ApiKeyStatus.failed;
    lastError = error;
    failureCount++;
    Log.w('[ApiKeyManager] Key #$index marked as failed: $error');
  }

  /// Mark key as exhausted (rate limited)
  void markExhausted() {
    status = ApiKeyStatus.exhausted;
    lastError = 'Rate limit exceeded';
    failureCount++;
    Log.w('[ApiKeyManager] Key #$index marked as exhausted (rate limited)');
  }

  /// Mark key as invalid
  void markInvalid() {
    status = ApiKeyStatus.invalid;
    lastError = 'API key invalid or revoked';
    failureCount++;
    Log.e('[ApiKeyManager] Key #$index marked as invalid');
  }

  /// Reset key to active status (session restart)
  void reset() {
    status = ApiKeyStatus.active;
    lastError = null;
    failureCount = 0;
    Log.i('[ApiKeyManager] Key #$index reset to active status');
  }

  /// Update last used timestamp
  void markUsed() {
    lastUsed = DateTime.now();
  }

  @override
  String toString() =>
      'ApiKeyInfo(index: $index, status: $status, failures: $failureCount)';
}

/// Dynamic API Key Manager for multiple providers
class ApiKeyManager {
  static final Map<String, List<ApiKeyInfo>> _providerKeys = {};
  static final Map<String, int> _currentKeyIndex = {};

  /// Load API keys for a provider from environment
  static List<ApiKeyInfo> loadKeysForProvider(final String providerId) {
    final cacheKey = providerId.toLowerCase();

    // Return cached keys if available
    if (_providerKeys.containsKey(cacheKey)) {
      return _providerKeys[cacheKey]!;
    }

    final keys = <ApiKeyInfo>[];

    try {
      // Try JSON array format first: PROVIDER_API_KEYS=["key1", "key2"]
      final envKey = '${providerId.toUpperCase()}_API_KEYS';
      final rawKeys = Config.parseApiKeysFromJson(envKey);

      // Convert to ApiKeyInfo objects
      for (int i = 0; i < rawKeys.length; i++) {
        final key = rawKeys[i].trim();
        if (key.isNotEmpty) {
          keys.add(ApiKeyInfo(key: key, index: i));
        }
      }

      if (keys.isNotEmpty) {
        Log.i(
          '[ApiKeyManager] Loaded ${keys.length} keys for $providerId from JSON array',
        );
      }

      // Fallback: try single key format: PROVIDER_API_KEY=key
      if (keys.isEmpty) {
        final singleKeyEnv = '${providerId.toUpperCase()}_API_KEY';
        final singleKey = Config.get(singleKeyEnv, '').trim();
        if (singleKey.isNotEmpty) {
          keys.add(ApiKeyInfo(key: singleKey, index: 0));
          Log.i(
            '[ApiKeyManager] Loaded 1 key for $providerId from single key format',
          );
        }
      }

      // Fallback: try numbered format: PROVIDER_API_KEY_1, PROVIDER_API_KEY_2, etc.
      if (keys.isEmpty) {
        for (int i = 1; i <= 10; i++) {
          // Check up to 10 keys
          final numberedKey = Config.get(
            '${providerId.toUpperCase()}_API_KEY_$i',
            '',
          ).trim();
          if (numberedKey.isNotEmpty) {
            keys.add(ApiKeyInfo(key: numberedKey, index: i - 1));
          } else {
            break; // Stop if we find a gap
          }
        }

        if (keys.isNotEmpty) {
          Log.i(
            '[ApiKeyManager] Loaded ${keys.length} keys for $providerId from numbered format',
          );
        }
      }

      // Cache the keys
      _providerKeys[cacheKey] = keys;

      if (keys.isNotEmpty) {
        _currentKeyIndex[cacheKey] = 0;
      }

      if (keys.isEmpty) {
        Log.w('[ApiKeyManager] No API keys found for provider: $providerId');
      }
    } on Exception catch (e) {
      Log.e('[ApiKeyManager] Error loading keys for $providerId: $e');
    }

    return keys;
  }

  /// Get the next available API key for a provider
  static String? getNextAvailableKey(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    if (keys.isEmpty) return null;

    final cacheKey = providerId.toLowerCase();
    final currentIndex = _currentKeyIndex[cacheKey] ?? 0;

    // Try to find an available key starting from current index
    for (int i = 0; i < keys.length; i++) {
      final index = (currentIndex + i) % keys.length;
      final keyInfo = keys[index];

      if (keyInfo.isAvailable) {
        _currentKeyIndex[cacheKey] = index;
        keyInfo.markUsed();

        Log.d('[ApiKeyManager] Using key #$index for $providerId');
        return keyInfo.key;
      }
    }

    Log.w('[ApiKeyManager] No available keys for provider: $providerId');
    return null;
  }

  /// Mark current key as failed and rotate to next
  static void markCurrentKeyFailed(
    final String providerId,
    final String error,
  ) {
    final keys = loadKeysForProvider(providerId);
    if (keys.isEmpty) return;

    final cacheKey = providerId.toLowerCase();
    final currentIndex = _currentKeyIndex[cacheKey] ?? 0;

    if (currentIndex < keys.length) {
      keys[currentIndex].markFailed(error);

      // Move to next key for next request
      _currentKeyIndex[cacheKey] = (currentIndex + 1) % keys.length;

      Log.i('[ApiKeyManager] Rotated $providerId to next key after failure');
    }
  }

  /// Mark current key as rate limited
  static void markCurrentKeyExhausted(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    if (keys.isEmpty) return;

    final cacheKey = providerId.toLowerCase();
    final currentIndex = _currentKeyIndex[cacheKey] ?? 0;

    if (currentIndex < keys.length) {
      keys[currentIndex].markExhausted();

      // Move to next key for next request
      _currentKeyIndex[cacheKey] = (currentIndex + 1) % keys.length;

      Log.i('[ApiKeyManager] Rotated $providerId to next key after rate limit');
    }
  }

  /// Reset all keys for a provider (session restart)
  static void resetKeysForProvider(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    for (final key in keys) {
      key.reset();
    }

    final cacheKey = providerId.toLowerCase();
    _currentKeyIndex[cacheKey] = 0;

    Log.i('[ApiKeyManager] Reset all keys for $providerId');
  }

  /// Reset all keys for all providers (app restart)
  static void resetAllKeys() {
    for (final providerId in _providerKeys.keys) {
      resetKeysForProvider(providerId);
    }
    Log.i('[ApiKeyManager] Reset all keys for all providers');
  }

  /// Get statistics for a provider
  static Map<String, dynamic> getProviderStats(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    final stats = <String, dynamic>{
      'total_keys': keys.length,
      'active_keys': keys
          .where((final k) => k.status == ApiKeyStatus.active)
          .length,
      'failed_keys': keys
          .where((final k) => k.status == ApiKeyStatus.failed)
          .length,
      'exhausted_keys': keys
          .where((final k) => k.status == ApiKeyStatus.exhausted)
          .length,
      'invalid_keys': keys
          .where((final k) => k.status == ApiKeyStatus.invalid)
          .length,
      'current_index': _currentKeyIndex[providerId.toLowerCase()] ?? 0,
    };

    return stats;
  }

  /// Get all provider statistics
  static Map<String, dynamic> getAllStats() {
    final allStats = <String, dynamic>{};

    for (final providerId in _providerKeys.keys) {
      allStats[providerId] = getProviderStats(providerId);
    }

    return allStats;
  }

  /// Check if provider has any available keys
  static bool hasAvailableKeys(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    return keys.any((final key) => key.isAvailable);
  }

  /// Get current key info for debugging
  static ApiKeyInfo? getCurrentKeyInfo(final String providerId) {
    final keys = loadKeysForProvider(providerId);
    if (keys.isEmpty) return null;

    final cacheKey = providerId.toLowerCase();
    final currentIndex = _currentKeyIndex[cacheKey] ?? 0;

    if (currentIndex < keys.length) {
      return keys[currentIndex];
    }

    return null;
  }
}
