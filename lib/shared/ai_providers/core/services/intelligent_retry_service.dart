/// Intelligent Retry Service implementation with exponential backoff
/// and circuit breaker patterns for enhanced reliability.
library;

import 'dart:async';
import 'dart:math';
import 'dart:io';
import '../../../utils/log_utils.dart';
import '../interfaces/i_retry_service.dart';

/// Provider-specific circuit breaker
class _CircuitBreaker {
  _CircuitBreaker(this.providerId, this.config);
  final String providerId;
  final CircuitBreakerConfig config;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _openedAt;
  DateTime? _halfOpenAt;
  final List<DateTime> _recentFailures = <DateTime>[];

  CircuitBreakerStatus get status => CircuitBreakerStatus(
    state: _state,
    failureCount: _failureCount,
    successCount: _successCount,
    openedAt: _openedAt,
    halfOpenAt: _halfOpenAt,
    nextRetryAt: _getNextRetryTime(),
  );

  bool canExecute() {
    _cleanupOldFailures();

    switch (_state) {
      case CircuitBreakerState.closed:
        return true;

      case CircuitBreakerState.open:
        if (_shouldAttemptRecovery()) {
          _transitionToHalfOpen();
          return true;
        }
        return false;

      case CircuitBreakerState.halfOpen:
        // Allow limited requests in half-open state
        final random = Random();
        return random.nextDouble() < config.halfOpenRequestPercent;
    }
  }

  void recordSuccess() {
    switch (_state) {
      case CircuitBreakerState.closed:
        _failureCount = 0;
        break;

      case CircuitBreakerState.halfOpen:
        _successCount++;
        if (_successCount >= config.successThreshold) {
          _transitionToClosed();
        }
        break;

      case CircuitBreakerState.open:
        // Should not happen, but reset if it does
        _transitionToClosed();
        break;
    }
  }

  void recordFailure() {
    final now = DateTime.now();
    _recentFailures.add(now);
    _failureCount++;

    switch (_state) {
      case CircuitBreakerState.closed:
        if (_failureCount >= config.failureThreshold) {
          _transitionToOpen();
        }
        break;

      case CircuitBreakerState.halfOpen:
        _transitionToOpen();
        break;

      case CircuitBreakerState.open:
        // Already open, just record the failure
        break;
    }
  }

  void forceOpen(final String reason) {
    Log.w('Manually opening circuit for $providerId: $reason');
    _transitionToOpen();
  }

  void forceClose() {
    Log.i('Manually closing circuit for $providerId');
    _transitionToClosed();
  }

  void _transitionToClosed() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _successCount = 0;
    _openedAt = null;
    _halfOpenAt = null;
    _recentFailures.clear();
    Log.i('Circuit closed for $providerId');
  }

  void _transitionToOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now();
    _halfOpenAt = null;
    _successCount = 0;
    Log.w('Circuit opened for $providerId (failures: $_failureCount)');
  }

  void _transitionToHalfOpen() {
    _state = CircuitBreakerState.halfOpen;
    _halfOpenAt = DateTime.now();
    _successCount = 0;
    Log.i('Circuit half-open for $providerId');
  }

  bool _shouldAttemptRecovery() {
    if (_openedAt == null) return false;
    final elapsed = DateTime.now().difference(_openedAt!);
    return elapsed.inMilliseconds >= config.recoveryTimeoutMs;
  }

  DateTime? _getNextRetryTime() {
    if (_state != CircuitBreakerState.open || _openedAt == null) return null;
    return _openedAt!.add(Duration(milliseconds: config.recoveryTimeoutMs));
  }

  void _cleanupOldFailures() {
    final cutoff = DateTime.now().subtract(
      Duration(milliseconds: config.failureWindowMs),
    );
    _recentFailures.removeWhere((final failure) => failure.isBefore(cutoff));
    _failureCount = _recentFailures.length;
  }
}

/// Provider-specific retry statistics
class _ProviderStats {
  int totalOperations = 0;
  int immediateSuccesses = 0;
  int eventualSuccesses = 0;
  int totalFailures = 0;
  int totalRetryAttempts = 0;
  int circuitBreakerTrips = 0;

  double get averageAttempts =>
      totalOperations > 0 ? totalRetryAttempts / totalOperations : 0.0;
  double get eventualSuccessRate =>
      totalOperations > 0 ? eventualSuccesses / totalOperations : 0.0;
}

/// Intelligent Retry Service implementation
class IntelligentRetryService implements IRetryService {
  late RetryConfig _defaultConfig;
  late CircuitBreakerConfig _circuitConfig;
  final Map<String, _CircuitBreaker> _circuitBreakers =
      <String, _CircuitBreaker>{};
  final Map<String, _ProviderStats> _providerStats = <String, _ProviderStats>{};
  final _ProviderStats _globalStats = _ProviderStats();
  final Random _random = Random();
  bool _isInitialized = false;

  @override
  Future<void> initialize(
    final RetryConfig defaultConfig,
    final CircuitBreakerConfig circuitConfig,
  ) async {
    if (_isInitialized) {
      Log.i('Retry service already initialized');
      return;
    }

    _defaultConfig = defaultConfig;
    _circuitConfig = circuitConfig;
    _isInitialized = true;

    Log.i(
      'Initialized with maxAttempts=${defaultConfig.maxAttempts}, '
      'circuitThreshold=${circuitConfig.failureThreshold}',
    );
  }

  @override
  Future<T> executeWithRetry<T>(
    final Future<T> Function() operation,
    final String providerId, {
    final RetryConfig? config,
    final void Function(RetryAttempt attempt)? onRetry,
  }) async {
    if (!_isInitialized) {
      throw StateError('Retry service not initialized');
    }

    final retryConfig = config ?? _defaultConfig;
    final circuitBreaker = _getOrCreateCircuitBreaker(providerId);
    final providerStats = _getOrCreateProviderStats(providerId);
    final stopwatch = Stopwatch()..start();

    providerStats.totalOperations++;
    _globalStats.totalOperations++;

    // Check circuit breaker before attempting
    if (!circuitBreaker.canExecute()) {
      providerStats.totalFailures++;
      _globalStats.totalFailures++;
      throw StateError('Circuit breaker is open for provider: $providerId');
    }

    Object? lastError;
    for (int attempt = 1; attempt <= retryConfig.maxAttempts; attempt++) {
      try {
        // Add delay before retry attempts (not for first attempt)
        if (attempt > 1) {
          final delayMs = calculateDelay(attempt - 1, retryConfig);
          final retryAttempt = RetryAttempt(
            attemptNumber: attempt,
            delayMs: delayMs,
            totalElapsed: stopwatch.elapsed,
            previousError: lastError,
            isFinalAttempt: attempt == retryConfig.maxAttempts,
          );

          onRetry?.call(retryAttempt);
          Log.d(
            'Retrying $providerId operation, attempt $attempt/${retryConfig.maxAttempts}, delay ${delayMs}ms',
          );

          await Future.delayed(Duration(milliseconds: delayMs));
          providerStats.totalRetryAttempts++;
          _globalStats.totalRetryAttempts++;
        }

        // Execute the operation with timeout
        final result = await operation().timeout(
          Duration(milliseconds: retryConfig.attemptTimeoutMs),
        );

        // Success - record metrics and return
        circuitBreaker.recordSuccess();
        if (attempt == 1) {
          providerStats.immediateSuccesses++;
          _globalStats.immediateSuccesses++;
        } else {
          providerStats.eventualSuccesses++;
          _globalStats.eventualSuccesses++;
        }

        Log.d('Operation succeeded for $providerId on attempt $attempt');
        return result;
      } on Object catch (error) {
        lastError = error;

        // Check if we should retry this error
        if (!shouldRetry(error, retryConfig, attempt)) {
          Log.d('Not retrying $providerId operation: ${error.runtimeType}');
          break;
        }

        // Don't record circuit breaker failure for the last attempt
        // (we'll record it below if all attempts fail)
        if (attempt < retryConfig.maxAttempts) {
          Log.d(
            'Operation failed for $providerId, attempt $attempt: ${error.runtimeType}',
          );
        }
      }
    }

    // All attempts failed - record failure
    circuitBreaker.recordFailure();
    providerStats.totalFailures++;
    _globalStats.totalFailures++;

    Log.w(
      'All retry attempts failed for $providerId: ${lastError.runtimeType}',
    );
    throw lastError!;
  }

  @override
  bool shouldRetry(
    final Object error,
    final RetryConfig config,
    final int attemptNumber,
  ) {
    // Don't retry if we've reached max attempts
    if (attemptNumber >= config.maxAttempts) return false;

    // Check error type
    if (error is SocketException && config.retryOnNetworkError) return true;
    if (error is TimeoutException && config.retryOnTimeout) return true;

    if (error is HttpException) {
      final statusCode = int.tryParse(error.message.split(' ').first) ?? 0;

      // Server errors (5xx)
      if (statusCode >= 500 && statusCode < 600 && config.retryOnServerError) {
        return true;
      }

      // Rate limiting (429)
      if (statusCode == 429 && config.retryOnRateLimit) return true;

      // Custom status codes
      if (config.retryOnStatusCodes.contains(statusCode)) return true;
    }

    return false;
  }

  @override
  int calculateDelay(final int attemptNumber, final RetryConfig config) {
    // Calculate exponential backoff delay
    final baseDelay =
        config.initialDelayMs *
        pow(config.backoffMultiplier, attemptNumber - 1);

    // Apply maximum delay limit
    final delayMs = min(baseDelay, config.maxDelayMs.toDouble()).toInt();

    // Add jitter to avoid thundering herd
    final jitterRange = (delayMs * config.jitterFactor).toInt();
    final jitter = _random.nextInt(jitterRange * 2) - jitterRange;

    return max(0, delayMs + jitter);
  }

  @override
  CircuitBreakerStatus getCircuitBreakerStatus(final String providerId) {
    final circuitBreaker = _circuitBreakers[providerId];
    return circuitBreaker?.status ??
        const CircuitBreakerStatus(
          state: CircuitBreakerState.closed,
          failureCount: 0,
          successCount: 0,
        );
  }

  @override
  void openCircuitBreaker(final String providerId, final String reason) {
    final circuitBreaker = _getOrCreateCircuitBreaker(providerId);
    circuitBreaker.forceOpen(reason);
    final providerStats = _getOrCreateProviderStats(providerId);
    providerStats.circuitBreakerTrips++;
    _globalStats.circuitBreakerTrips++;
  }

  @override
  void closeCircuitBreaker(final String providerId) {
    final circuitBreaker = _circuitBreakers[providerId];
    circuitBreaker?.forceClose();
  }

  @override
  RetryStats getStats() {
    final circuitStates = <String, CircuitBreakerStatus>{};
    for (final entry in _circuitBreakers.entries) {
      circuitStates[entry.key] = entry.value.status;
    }

    return RetryStats(
      totalOperations: _globalStats.totalOperations,
      immediateSuccesses: _globalStats.immediateSuccesses,
      eventualSuccesses: _globalStats.eventualSuccesses,
      totalFailures: _globalStats.totalFailures,
      totalRetryAttempts: _globalStats.totalRetryAttempts,
      averageAttempts: _globalStats.averageAttempts,
      eventualSuccessRate: _globalStats.eventualSuccessRate,
      circuitBreakerTrips: _globalStats.circuitBreakerTrips,
      circuitBreakerStates: circuitStates,
    );
  }

  @override
  RetryStats getProviderStats(final String providerId) {
    final providerStats = _providerStats[providerId];
    final circuitBreaker = _circuitBreakers[providerId];

    if (providerStats == null) {
      return const RetryStats(
        totalOperations: 0,
        immediateSuccesses: 0,
        eventualSuccesses: 0,
        totalFailures: 0,
        totalRetryAttempts: 0,
        averageAttempts: 0.0,
        eventualSuccessRate: 0.0,
        circuitBreakerTrips: 0,
        circuitBreakerStates: {},
      );
    }

    final circuitStates = <String, CircuitBreakerStatus>{};
    if (circuitBreaker != null) {
      circuitStates[providerId] = circuitBreaker.status;
    }

    return RetryStats(
      totalOperations: providerStats.totalOperations,
      immediateSuccesses: providerStats.immediateSuccesses,
      eventualSuccesses: providerStats.eventualSuccesses,
      totalFailures: providerStats.totalFailures,
      totalRetryAttempts: providerStats.totalRetryAttempts,
      averageAttempts: providerStats.averageAttempts,
      eventualSuccessRate: providerStats.eventualSuccessRate,
      circuitBreakerTrips: providerStats.circuitBreakerTrips,
      circuitBreakerStates: circuitStates,
    );
  }

  @override
  void resetStats() {
    _globalStats.totalOperations = 0;
    _globalStats.immediateSuccesses = 0;
    _globalStats.eventualSuccesses = 0;
    _globalStats.totalFailures = 0;
    _globalStats.totalRetryAttempts = 0;
    _globalStats.circuitBreakerTrips = 0;

    _providerStats.clear();
    Log.i('Reset all retry statistics');
  }

  @override
  void resetProviderStats(final String providerId) {
    _providerStats.remove(providerId);
    Log.i('Reset retry statistics for $providerId');
  }

  // Private helper methods

  _CircuitBreaker _getOrCreateCircuitBreaker(final String providerId) {
    return _circuitBreakers.putIfAbsent(
      providerId,
      () => _CircuitBreaker(providerId, _circuitConfig),
    );
  }

  _ProviderStats _getOrCreateProviderStats(final String providerId) {
    return _providerStats.putIfAbsent(providerId, () => _ProviderStats());
  }
}
