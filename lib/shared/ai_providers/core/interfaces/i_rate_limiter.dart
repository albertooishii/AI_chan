/// Rate Limiting System interface for AI provider requests
///
/// Provides token bucket, sliding window, and adaptive rate limiting
/// algorithms to manage provider API quotas and prevent abuse.
library;

import 'dart:async';

/// Rate limiting algorithm types
enum RateLimitAlgorithm {
  /// Token bucket algorithm - allows bursts
  tokenBucket,

  /// Fixed window counter - simple but can have burst issues
  fixedWindow,

  /// Sliding window log - precise but memory intensive
  slidingWindowLog,

  /// Sliding window counter - good balance of precision and efficiency
  slidingWindowCounter,

  /// Adaptive rate limiting - adjusts based on provider response
  adaptive,
}

/// Rate limit configuration
class RateLimitConfig {
  const RateLimitConfig({
    required this.maxRequests,
    required this.windowMs,
    this.algorithm = RateLimitAlgorithm.tokenBucket,
    final double? refillRate,
    final int? burstSize,
    this.enableAdaptive = true,
    this.adaptiveScaleFactor = 0.7,
    this.adaptiveRecoveryMs = 60000, // 1 minute
    this.queueSize = 100,
    this.queueTimeoutMs = 30000, // 30 seconds
  }) : refillRate = refillRate ?? (maxRequests / (windowMs / 1000)),
       burstSize = burstSize ?? maxRequests;

  /// Create configuration for high-volume provider (e.g., OpenAI)
  const RateLimitConfig.highVolume()
    : this(
        maxRequests: 1000,
        windowMs: 60000, // 1 minute
        algorithm: RateLimitAlgorithm.tokenBucket,
        burstSize: 100,
      );

  /// Create configuration for moderate-volume provider (e.g., Google)
  const RateLimitConfig.moderate()
    : this(
        maxRequests: 300,
        windowMs: 60000, // 1 minute
        algorithm: RateLimitAlgorithm.slidingWindowCounter,
        burstSize: 30,
      );

  /// Create configuration for low-volume provider (e.g., specialized APIs)
  const RateLimitConfig.lowVolume()
    : this(
        maxRequests: 60,
        windowMs: 60000, // 1 minute
        algorithm: RateLimitAlgorithm.fixedWindow,
        burstSize: 10,
      );

  /// Maximum requests per time window
  final int maxRequests;

  /// Time window in milliseconds
  final int windowMs;

  /// Rate limiting algorithm to use
  final RateLimitAlgorithm algorithm;

  /// Token refill rate for token bucket (tokens per second)
  final double refillRate;

  /// Maximum burst size for token bucket
  final int burstSize;

  /// Enable adaptive rate limiting
  final bool enableAdaptive;

  /// Adaptive scaling factor (0.5 = reduce by 50% on errors)
  final double adaptiveScaleFactor;

  /// Time to recover from adaptive scaling in milliseconds
  final int adaptiveRecoveryMs;

  /// Queue size for throttled requests
  final int queueSize;

  /// Request timeout in queue in milliseconds
  final int queueTimeoutMs;
}

/// Rate limit check result
class RateLimitResult {
  const RateLimitResult({
    required this.isAllowed,
    required this.available,
    required this.limit,
    required this.retryAfterMs,
    required this.queueLength,
    required this.estimatedWaitMs,
    required this.algorithm,
    required this.isAdaptiveScaled,
    required this.adaptiveScale,
  });

  /// Whether the request is allowed
  final bool isAllowed;

  /// Current number of available requests/tokens
  final int available;

  /// Maximum requests/tokens
  final int limit;

  /// Time until next token/window reset in milliseconds
  final int retryAfterMs;

  /// Current requests in queue
  final int queueLength;

  /// Estimated wait time if queued in milliseconds
  final int estimatedWaitMs;

  /// Rate limit algorithm used
  final RateLimitAlgorithm algorithm;

  /// Whether adaptive scaling is active
  final bool isAdaptiveScaled;

  /// Current adaptive scale factor (1.0 = normal, 0.5 = 50% reduced)
  final double adaptiveScale;
}

/// Rate limiting statistics
class RateLimitStats {
  const RateLimitStats({
    required this.totalRequests,
    required this.allowedRequests,
    required this.blockedRequests,
    required this.queuedRequests,
    required this.droppedRequests,
    required this.currentQueueLength,
    required this.averageQueueWaitMs,
    required this.successRate,
    required this.utilization,
    required this.adaptiveScalingEvents,
    required this.currentAdaptiveScale,
  });

  /// Total requests processed
  final int totalRequests;

  /// Requests allowed immediately
  final int allowedRequests;

  /// Requests blocked by rate limit
  final int blockedRequests;

  /// Requests queued and later processed
  final int queuedRequests;

  /// Requests dropped from queue (timeout/overflow)
  final int droppedRequests;

  /// Current queue length
  final int currentQueueLength;

  /// Average wait time in queue in milliseconds
  final double averageQueueWaitMs;

  /// Success rate (0.0 - 1.0)
  final double successRate;

  /// Current rate limit utilization (0.0 - 1.0)
  final double utilization;

  /// Adaptive scaling events
  final int adaptiveScalingEvents;

  /// Current adaptive scale factor
  final double currentAdaptiveScale;
}

/// Queued request information
class QueuedRequest {
  QueuedRequest({
    required this.id,
    required this.queuedAt,
    required this.completer,
    this.metadata = const {},
  });

  /// Unique request identifier
  final String id;

  /// Timestamp when request was queued
  final DateTime queuedAt;

  /// Request completer for async processing
  final Completer<bool> completer;

  /// Request metadata
  final Map<String, dynamic> metadata;

  /// How long the request has been in queue
  Duration get queueTime => DateTime.now().difference(queuedAt);
}

/// Rate Limiter interface
abstract class IRateLimiter {
  /// Initialize the rate limiter with configuration
  Future<void> initialize(final Map<String, RateLimitConfig> providerConfigs);

  /// Check if a request is allowed for a provider
  ///
  /// Returns immediately with rate limit decision.
  /// Use [executeWithRateLimit] for automatic queuing.
  RateLimitResult checkRateLimit(
    final String providerId, {
    final Map<String, dynamic>? metadata,
  });

  /// Execute a request with rate limiting and optional queuing
  ///
  /// Will queue the request if rate limited and queuing is enabled.
  /// Returns when the request can proceed or times out.
  Future<T> executeWithRateLimit<T>(
    final String providerId,
    final Future<T> Function() operation, {
    final Map<String, dynamic>? metadata,
    final Duration? timeout,
  });

  /// Reserve a token/slot for a future request
  ///
  /// Useful for batch operations where you want to check
  /// availability before starting expensive operations.
  Future<String> reserveSlot(
    final String providerId, {
    final Map<String, dynamic>? metadata,
  });

  /// Release a reserved slot (if request won't be made)
  void releaseSlot(final String providerId, final String reservationId);

  /// Consume a reserved slot (when making the actual request)
  bool consumeReservedSlot(final String providerId, final String reservationId);

  /// Record a successful request (for adaptive rate limiting)
  void recordSuccess(final String providerId, final int responseTimeMs);

  /// Record a failed request (for adaptive rate limiting)
  void recordFailure(
    final String providerId,
    final String errorType,
    final int? statusCode,
  );

  /// Manually adjust rate limit for a provider
  void adjustRateLimit(
    final String providerId,
    final RateLimitConfig newConfig,
  );

  /// Get current rate limit status for a provider
  RateLimitResult getStatus(final String providerId);

  /// Get rate limiting statistics for a provider
  RateLimitStats getStats(final String providerId);

  /// Get global rate limiting statistics
  RateLimitStats getGlobalStats();

  /// Get current queue status for a provider
  List<QueuedRequest> getQueueStatus(final String providerId);

  /// Clear the queue for a provider (cancel all pending requests)
  int clearQueue(final String providerId);

  /// Reset rate limiting state for a provider
  void resetProvider(final String providerId);

  /// Reset all rate limiting state
  void resetAll();

  /// Enable/disable rate limiting
  void setEnabled(final bool enabled);

  /// Check if rate limiting is enabled
  bool get isEnabled;
}
