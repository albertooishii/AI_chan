/// In-memory cache implementation for AI provider responses
/// with TTL, size limits, and performance monitoring.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ai_chan/shared.dart';

/// In-memory cache service with LRU eviction and TTL support
class InMemoryCacheService implements ICacheService {
  InMemoryCacheService([final CacheConfig? config])
    : _config = config ?? const CacheConfig() {
    _startCleanupTimer();
  }

  final CacheConfig _config;
  final LinkedHashMap<String, CacheEntry<AIResponse>> _cache = LinkedHashMap();
  Timer? _cleanupTimer;

  // Statistics
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  @override
  Future<AIResponse?> get(final CacheKey key) async {
    final keyStr = key.toString();
    final entry = _cache[keyStr];

    if (entry == null) {
      _misses++;
      return null;
    }

    if (entry.isExpired) {
      _cache.remove(keyStr);
      _misses++;
      return null;
    }

    // Move to end (LRU)
    _cache.remove(keyStr);
    _cache[keyStr] = entry;

    _hits++;
    return entry.data;
  }

  @override
  Future<void> set(
    final CacheKey key,
    final AIResponse response, {
    final Duration? ttl,
    final Map<String, dynamic>? metadata,
  }) async {
    final keyStr = key.toString();
    final effectiveTTL = ttl ?? _config.defaultTTL;

    // Create cache entry
    final entry = CacheEntry<AIResponse>(
      data: response,
      timestamp: DateTime.now(),
      ttl: effectiveTTL,
      metadata: metadata ?? {},
    );

    // Check size limit and evict if necessary
    if (_cache.length >= _config.maxSize) {
      _evictLRU();
    }

    _cache[keyStr] = entry;
    Log.d('[Cache] Stored entry: $keyStr (TTL: ${effectiveTTL.inMinutes}m)');
  }

  @override
  Future<void> remove(final CacheKey key) async {
    final keyStr = key.toString();
    final removed = _cache.remove(keyStr);
    if (removed != null) {
      Log.d('[Cache] Removed entry: $keyStr');
    }
  }

  @override
  Future<void> clear() async {
    final count = _cache.length;
    _cache.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    Log.i('[Cache] Cleared all entries ($count items)');
  }

  @override
  Future<void> clearExpired() async {
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      Log.d('[Cache] Cleared ${keysToRemove.length} expired entries');
    }
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    final totalRequests = _hits + _misses;
    final hitRate = totalRequests > 0 ? _hits / totalRequests : 0.0;

    return {
      'cache_type': 'in_memory',
      'entries': _cache.length,
      'max_size': _config.maxSize,
      'hits': _hits,
      'misses': _misses,
      'evictions': _evictions,
      'hit_rate': hitRate,
      'total_requests': totalRequests,
      'memory_usage_estimate': _estimateMemoryUsage(),
      'default_ttl_minutes': _config.defaultTTL.inMinutes,
    };
  }

  @override
  void setSizeLimit(final int limit) {
    // Note: Cannot modify final config, would need to recreate service
    Log.w('[Cache] setSizeLimit not supported in this implementation');
  }

  @override
  void setDefaultTTL(final Duration ttl) {
    // Note: Cannot modify final config, would need to recreate service
    Log.w('[Cache] setDefaultTTL not supported in this implementation');
  }

  @override
  Future<bool> contains(final CacheKey key) async {
    final keyStr = key.toString();
    final entry = _cache[keyStr];

    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(keyStr);
      return false;
    }

    return true;
  }

  @override
  Future<double> getHitRate() async {
    final totalRequests = _hits + _misses;
    return totalRequests > 0 ? _hits / totalRequests : 0.0;
  }

  @override
  Future<void> invalidateByPattern({
    final String? providerId,
    final String? model,
    final String? capability,
  }) async {
    final keysToRemove = <String>[];

    for (final key in _cache.keys) {
      bool matches = true;

      if (providerId != null && !key.contains('${providerId}_')) {
        matches = false;
      }
      if (model != null && !key.contains('_${model}_')) {
        matches = false;
      }
      if (capability != null && !key.contains('_${capability}_')) {
        matches = false;
      }

      if (matches) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      Log.d('[Cache] Invalidated ${keysToRemove.length} entries by pattern');
    }
  }

  /// Evict least recently used entry
  void _evictLRU() {
    if (_cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
      _evictions++;
      Log.d('[Cache] Evicted LRU entry: $firstKey');
    }
  }

  /// Start periodic cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_config.cleanupInterval, (_) {
      clearExpired();
    });
  }

  /// Estimate memory usage (rough approximation)
  int _estimateMemoryUsage() {
    int totalBytes = 0;

    for (final entry in _cache.entries) {
      final keyBytes = utf8.encode(entry.key).length;
      final valueBytes = utf8.encode(entry.value.data.text).length;
      totalBytes += keyBytes + valueBytes + 200; // Overhead estimate
    }

    return totalBytes;
  }

  /// Cleanup resources
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
    Log.d('[Cache] Disposed cache service');
  }
}
