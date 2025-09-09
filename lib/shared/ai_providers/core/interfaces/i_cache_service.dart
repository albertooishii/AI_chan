/// Interface for caching AI provider responses to improve performance
/// and reduce API calls for repeated requests.
library;

import 'dart:async';
import 'package:ai_chan/core/models/ai_response.dart';

/// Cache entry with TTL and metadata
class CacheEntry<T> {
  const CacheEntry({
    required this.data,
    required this.timestamp,
    required this.ttl,
    this.metadata = const {},
  });

  final T data;
  final DateTime timestamp;
  final Duration ttl;
  final Map<String, dynamic> metadata;

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// Cache key for AI requests
class CacheKey {
  const CacheKey({
    required this.providerId,
    required this.model,
    required this.capability,
    required this.messageHash,
    this.additionalData = const {},
  });

  final String providerId;
  final String model;
  final String capability;
  final String messageHash;
  final Map<String, dynamic> additionalData;

  @override
  String toString() {
    return '${providerId}_${model}_${capability}_${messageHash}_${additionalData.hashCode}';
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is CacheKey &&
        other.providerId == providerId &&
        other.model == model &&
        other.capability == capability &&
        other.messageHash == messageHash &&
        other.additionalData.toString() == additionalData.toString();
  }

  @override
  int get hashCode {
    return Object.hash(
      providerId,
      model,
      capability,
      messageHash,
      additionalData.hashCode,
    );
  }
}

/// Interface for caching AI provider responses
abstract class ICacheService {
  /// Get cached response for a given key
  Future<AIResponse?> get(final CacheKey key);

  /// Store response in cache with TTL
  Future<void> set(
    final CacheKey key,
    final AIResponse response, {
    final Duration? ttl,
    final Map<String, dynamic>? metadata,
  });

  /// Remove entry from cache
  Future<void> remove(final CacheKey key);

  /// Clear all cache entries
  Future<void> clear();

  /// Clear expired entries
  Future<void> clearExpired();

  /// Get cache statistics
  Future<Map<String, dynamic>> getStats();

  /// Set cache size limit (number of entries)
  void setSizeLimit(final int limit);

  /// Set default TTL for cache entries
  void setDefaultTTL(final Duration ttl);

  /// Check if cache contains key
  Future<bool> contains(final CacheKey key);

  /// Get cache hit rate
  Future<double> getHitRate();

  /// Invalidate cache entries by pattern
  Future<void> invalidateByPattern({
    final String? providerId,
    final String? model,
    final String? capability,
  });
}

/// Cache configuration options
class CacheConfig {
  const CacheConfig({
    this.defaultTTL = const Duration(minutes: 15),
    this.maxSize = 1000,
    this.enableCompression = true,
    this.enableStats = true,
    this.cleanupInterval = const Duration(minutes: 5),
  });

  final Duration defaultTTL;
  final int maxSize;
  final bool enableCompression;
  final bool enableStats;
  final Duration cleanupInterval;
}
