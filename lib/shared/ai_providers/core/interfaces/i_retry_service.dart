/// Intelligent Retry System interface for AI provider requests
///
/// Provides exponential backoff, circuit breaker patterns, and
/// provider-specific retry logic for enhanced reliability.
library;

/// Retry configuration for different types of failures
class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelayMs = 1000,
    this.maxDelayMs = 30000,
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.attemptTimeoutMs = 30000,
    this.retryOnNetworkError = true,
    this.retryOnTimeout = true,
    this.retryOnServerError = true,
    this.retryOnRateLimit = true,
    this.retryOnStatusCodes = const {502, 503, 504},
  });

  /// Create configuration for aggressive retries (e.g., critical requests)
  const RetryConfig.aggressive()
    : this(
        maxAttempts: 5,
        initialDelayMs: 500,
        maxDelayMs: 60000,
        backoffMultiplier: 1.5,
        jitterFactor: 0.2,
      );

  /// Create configuration for conservative retries (e.g., bulk operations)
  const RetryConfig.conservative()
    : this(
        maxAttempts: 2,
        initialDelayMs: 2000,
        maxDelayMs: 10000,
        backoffMultiplier: 2.0,
        jitterFactor: 0.05,
      );

  /// Create configuration with no retries
  const RetryConfig.noRetry() : this(maxAttempts: 1);

  /// Maximum number of retry attempts
  final int maxAttempts;

  /// Initial delay in milliseconds
  final int initialDelayMs;

  /// Maximum delay between retries in milliseconds
  final int maxDelayMs;

  /// Backoff multiplier for exponential backoff
  final double backoffMultiplier;

  /// Jitter factor to randomize delays (0.0 - 1.0)
  final double jitterFactor;

  /// Timeout for each individual attempt in milliseconds
  final int attemptTimeoutMs;

  /// Whether to retry on network errors
  final bool retryOnNetworkError;

  /// Whether to retry on timeout errors
  final bool retryOnTimeout;

  /// Whether to retry on server errors (5xx)
  final bool retryOnServerError;

  /// Whether to retry on rate limit errors (429)
  final bool retryOnRateLimit;

  /// Custom HTTP status codes to retry on
  final Set<int> retryOnStatusCodes;
}

/// Circuit breaker states
enum CircuitBreakerState {
  /// Normal operation - requests pass through
  closed,

  /// Failure threshold exceeded - requests fail fast
  open,

  /// Testing if service has recovered - limited requests allowed
  halfOpen,
}

/// Circuit breaker configuration
class CircuitBreakerConfig {
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.failureWindowMs = 60000, // 1 minute
    this.recoveryTimeoutMs = 30000, // 30 seconds
    this.successThreshold = 3,
    this.halfOpenRequestPercent = 0.1, // 10%
  });

  /// Number of failures to trigger circuit breaker
  final int failureThreshold;

  /// Time window for counting failures in milliseconds
  final int failureWindowMs;

  /// Time to wait before attempting recovery in milliseconds
  final int recoveryTimeoutMs;

  /// Number of successful requests needed to close circuit
  final int successThreshold;

  /// Percentage of requests to allow through in half-open state
  final double halfOpenRequestPercent;
}

/// Circuit breaker status
class CircuitBreakerStatus {
  const CircuitBreakerStatus({
    required this.state,
    required this.failureCount,
    required this.successCount,
    this.openedAt,
    this.halfOpenAt,
    this.nextRetryAt,
  });

  /// Current state of the circuit breaker
  final CircuitBreakerState state;

  /// Number of failures in current window
  final int failureCount;

  /// Number of successful requests in half-open state
  final int successCount;

  /// Time when circuit breaker opened
  final DateTime? openedAt;

  /// Time when circuit breaker last transitioned to half-open
  final DateTime? halfOpenAt;

  /// Next time recovery will be attempted
  final DateTime? nextRetryAt;
}

/// Retry attempt information
class RetryAttempt {
  const RetryAttempt({
    required this.attemptNumber,
    required this.delayMs,
    required this.totalElapsed,
    this.previousError,
    required this.isFinalAttempt,
  });

  /// Attempt number (1-based)
  final int attemptNumber;

  /// Delay before this attempt in milliseconds
  final int delayMs;

  /// Total elapsed time since first attempt
  final Duration totalElapsed;

  /// Error from previous attempt (if any)
  final Object? previousError;

  /// Whether this is the final attempt
  final bool isFinalAttempt;
}

/// Retry statistics for monitoring
class RetryStats {
  const RetryStats({
    required this.totalOperations,
    required this.immediateSuccesses,
    required this.eventualSuccesses,
    required this.totalFailures,
    required this.totalRetryAttempts,
    required this.averageAttempts,
    required this.eventualSuccessRate,
    required this.circuitBreakerTrips,
    required this.circuitBreakerStates,
  });

  /// Total number of operations attempted
  final int totalOperations;

  /// Number of operations that succeeded without retry
  final int immediateSuccesses;

  /// Number of operations that succeeded after retry
  final int eventualSuccesses;

  /// Number of operations that failed after all retries
  final int totalFailures;

  /// Total number of retry attempts across all operations
  final int totalRetryAttempts;

  /// Average number of attempts per operation
  final double averageAttempts;

  /// Success rate after retries (0.0 - 1.0)
  final double eventualSuccessRate;

  /// Circuit breaker trip count
  final int circuitBreakerTrips;

  /// Current circuit breaker states by provider
  final Map<String, CircuitBreakerStatus> circuitBreakerStates;
}

/// Intelligent Retry Service interface
abstract class IRetryService {
  /// Initialize the retry service with default configuration
  Future<void> initialize(
    final RetryConfig defaultConfig,
    final CircuitBreakerConfig circuitConfig,
  );

  /// Execute an operation with retry logic
  ///
  /// [operation] - The operation to execute
  /// [providerId] - Unique identifier for the provider (for circuit breaker)
  /// [config] - Optional retry configuration (uses default if not provided)
  /// [onRetry] - Optional callback called before each retry attempt
  Future<T> executeWithRetry<T>(
    final Future<T> Function() operation,
    final String providerId, {
    final RetryConfig? config,
    final void Function(RetryAttempt attempt)? onRetry,
  });

  /// Check if a request should be retried based on error
  bool shouldRetry(
    final Object error,
    final RetryConfig config,
    final int attemptNumber,
  );

  /// Calculate delay for next retry attempt
  int calculateDelay(final int attemptNumber, final RetryConfig config);

  /// Get circuit breaker status for a provider
  CircuitBreakerStatus getCircuitBreakerStatus(final String providerId);

  /// Manually open circuit breaker for a provider
  void openCircuitBreaker(final String providerId, final String reason);

  /// Manually close circuit breaker for a provider
  void closeCircuitBreaker(final String providerId);

  /// Get retry statistics for monitoring
  RetryStats getStats();

  /// Get provider-specific retry statistics
  RetryStats getProviderStats(final String providerId);

  /// Reset all statistics
  void resetStats();

  /// Reset statistics for a specific provider
  void resetProviderStats(final String providerId);
}
