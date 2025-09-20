/// Performance monitoring service for AI providers
/// Tracks metrics like response times, success rates, and error patterns
library;

import 'dart:math';

/// Performance metrics for a provider
class ProviderMetrics {
  ProviderMetrics(this.providerId);

  final String providerId;
  final List<int> _responseTimes = [];
  final List<bool> _successResults = [];
  final Map<String, int> _errorCounts = {};
  int _totalRequests = 0;
  DateTime? _lastRequestTime;
  DateTime? _firstRequestTime;

  /// Add a performance measurement
  void addMeasurement({
    required final int responseTimeMs,
    required final bool success,
    final String? errorType,
  }) {
    _totalRequests++;
    _responseTimes.add(responseTimeMs);
    _successResults.add(success);

    final now = DateTime.now();
    _lastRequestTime = now;
    _firstRequestTime ??= now;

    if (!success && errorType != null) {
      _errorCounts[errorType] = (_errorCounts[errorType] ?? 0) + 1;
    }

    // Keep only last 1000 measurements to prevent memory bloat
    if (_responseTimes.length > 1000) {
      _responseTimes.removeAt(0);
      _successResults.removeAt(0);
    }
  }

  /// Get average response time
  double get averageResponseTime {
    if (_responseTimes.isEmpty) return 0.0;
    return _responseTimes.reduce((final a, final b) => a + b) /
        _responseTimes.length;
  }

  /// Get median response time
  double get medianResponseTime {
    if (_responseTimes.isEmpty) return 0.0;
    final sorted = List<int>.from(_responseTimes)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// Get 95th percentile response time
  double get p95ResponseTime {
    if (_responseTimes.isEmpty) return 0.0;
    final sorted = List<int>.from(_responseTimes)..sort();
    final index = (sorted.length * 0.95).ceil() - 1;
    return sorted[min(index, sorted.length - 1)].toDouble();
  }

  /// Get success rate (0.0 to 1.0)
  double get successRate {
    if (_successResults.isEmpty) return 0.0;
    final successCount = _successResults.where((final s) => s).length;
    return successCount / _successResults.length;
  }

  /// Get error rate (0.0 to 1.0)
  double get errorRate => 1.0 - successRate;

  /// Get requests per minute (recent activity)
  double get requestsPerMinute {
    if (_firstRequestTime == null || _lastRequestTime == null) return 0.0;

    final duration = _lastRequestTime!.difference(_firstRequestTime!);
    if (duration.inMinutes == 0) return _totalRequests.toDouble();

    return _totalRequests / duration.inMinutes;
  }

  /// Get most common error types
  List<MapEntry<String, int>> get topErrors {
    final entries = _errorCounts.entries.toList();
    entries.sort((final a, final b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  /// Check if provider is healthy based on recent metrics
  bool get isHealthy {
    if (_successResults.length < 5) return true; // Not enough data

    // Check last 10 requests
    final recent = _successResults.length >= 10
        ? _successResults.sublist(_successResults.length - 10)
        : _successResults;

    final recentSuccessRate =
        recent.where((final s) => s).length / recent.length;
    final recentAvgTime = _responseTimes.length >= 10
        ? _responseTimes
                  .sublist(_responseTimes.length - 10)
                  .reduce((final a, final b) => a + b) /
              10
        : averageResponseTime;

    // Healthy if: success rate > 80% AND avg response time < 30 seconds
    return recentSuccessRate > 0.8 && recentAvgTime < 30000;
  }

  /// Get comprehensive metrics
  Map<String, dynamic> toMap() {
    return {
      'provider_id': providerId,
      'total_requests': _totalRequests,
      'avg_response_time_ms': averageResponseTime,
      'median_response_time_ms': medianResponseTime,
      'p95_response_time_ms': p95ResponseTime,
      'success_rate': successRate,
      'error_rate': errorRate,
      'requests_per_minute': requestsPerMinute,
      'is_healthy': isHealthy,
      'top_errors': Map.fromEntries(topErrors),
      'last_request': _lastRequestTime?.toIso8601String(),
      'first_request': _firstRequestTime?.toIso8601String(),
    };
  }
}

/// Performance monitoring service
class PerformanceMonitoringService {
  factory PerformanceMonitoringService() => _instance;
  PerformanceMonitoringService._internal();
  static final PerformanceMonitoringService _instance =
      PerformanceMonitoringService._internal();

  final Map<String, ProviderMetrics> _providerMetrics = {};

  /// Start timing a request
  DateTime startTiming() => DateTime.now();

  /// Record a completed request
  void recordRequest({
    required final String providerId,
    required final DateTime startTime,
    required final bool success,
    final String? errorType,
  }) {
    final responseTime = DateTime.now().difference(startTime).inMilliseconds;

    _providerMetrics.putIfAbsent(providerId, () => ProviderMetrics(providerId));
    _providerMetrics[providerId]!.addMeasurement(
      responseTimeMs: responseTime,
      success: success,
      errorType: errorType,
    );
  }

  /// Get metrics for a specific provider
  ProviderMetrics? getProviderMetrics(final String providerId) {
    return _providerMetrics[providerId];
  }

  /// Get provider health scores (sorted by health)
  List<MapEntry<String, double>> getProviderHealthScores() {
    final scores = <MapEntry<String, double>>[];

    for (final entry in _providerMetrics.entries) {
      final metrics = entry.value;

      // Health score calculation (0.0 to 1.0)
      final successWeight = 0.6;
      final speedWeight = 0.4;

      final successScore = metrics.successRate;
      final speedScore = _calculateSpeedScore(metrics.averageResponseTime);

      final healthScore =
          (successScore * successWeight) + (speedScore * speedWeight);
      scores.add(MapEntry(entry.key, healthScore));
    }

    // Sort by health score (descending)
    scores.sort((final a, final b) => b.value.compareTo(a.value));
    return scores;
  }

  /// Get fastest providers
  List<MapEntry<String, double>> getFastestProviders() {
    final speeds = <MapEntry<String, double>>[];

    for (final entry in _providerMetrics.entries) {
      speeds.add(MapEntry(entry.key, entry.value.averageResponseTime));
    }

    // Sort by speed (ascending - faster is better)
    speeds.sort((final a, final b) => a.value.compareTo(b.value));
    return speeds;
  }

  /// Get most reliable providers
  List<MapEntry<String, double>> getMostReliableProviders() {
    final reliability = <MapEntry<String, double>>[];

    for (final entry in _providerMetrics.entries) {
      reliability.add(MapEntry(entry.key, entry.value.successRate));
    }

    // Sort by success rate (descending)
    reliability.sort((final a, final b) => b.value.compareTo(a.value));
    return reliability;
  }

  /// Get overall system stats
  Map<String, dynamic> getSystemStats() {
    final totalRequests = _providerMetrics.values
        .map((final m) => m._totalRequests)
        .fold(0, (final sum, final count) => sum + count);

    final avgSuccessRate = _providerMetrics.values.isNotEmpty
        ? _providerMetrics.values
                  .map((final m) => m.successRate)
                  .reduce((final a, final b) => a + b) /
              _providerMetrics.length
        : 0.0;

    final avgResponseTime = _providerMetrics.values.isNotEmpty
        ? _providerMetrics.values
                  .map((final m) => m.averageResponseTime)
                  .reduce((final a, final b) => a + b) /
              _providerMetrics.length
        : 0.0;

    return {
      'total_providers': _providerMetrics.length,
      'total_requests': totalRequests,
      'avg_success_rate': avgSuccessRate,
      'avg_response_time_ms': avgResponseTime,
      'healthy_providers': _providerMetrics.values
          .where((final m) => m.isHealthy)
          .length,
      'providers': _providerMetrics.map(
        (final id, final metrics) => MapEntry(id, metrics.toMap()),
      ),
    };
  }

  /// Calculate speed score (1.0 = best, 0.0 = worst)
  double _calculateSpeedScore(final double avgResponseTimeMs) {
    // Excellent: < 1s, Good: < 5s, Poor: < 30s, Bad: > 30s
    if (avgResponseTimeMs < 1000) return 1.0;
    if (avgResponseTimeMs < 5000) return 0.8;
    if (avgResponseTimeMs < 15000) return 0.6;
    if (avgResponseTimeMs < 30000) return 0.4;
    return 0.2;
  }
}
