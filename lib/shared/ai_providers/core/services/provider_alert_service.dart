/// Provider Alert Service implementation for proactive monitoring
///
/// Provides real-time alerts, threshold monitoring, and notification
/// management for AI provider health and performance issues.
library;

import 'dart:async';
import 'dart:math';
import 'package:ai_chan/shared.dart';

/// Provider health tracker for alert calculations
class _ProviderHealthTracker {
  _ProviderHealthTracker(this.providerId, this.thresholds);
  final String providerId;
  final AlertThresholds thresholds;

  final List<_RequestMetric> _recentRequests = <_RequestMetric>[];
  int _consecutiveFailures = 0;
  bool _isDown = false;

  void recordRequest(final double responseTimeMs, final bool isError) {
    final now = DateTime.now();

    // Add request to recent requests
    _recentRequests.add(
      _RequestMetric(
        timestamp: now,
        responseTimeMs: responseTimeMs,
        isError: isError,
      ),
    );

    // Clean up old requests outside time window
    _cleanupOldRequests();

    // Update consecutive failures
    if (isError) {
      _consecutiveFailures++;
    } else {
      _consecutiveFailures = 0;
      _isDown = false;
    }

    // Check if provider should be marked as down
    if (_consecutiveFailures >= thresholds.unavailabilityThreshold) {
      _isDown = true;
    }
  }

  bool get isDown => _isDown;

  double get currentErrorRate {
    if (_recentRequests.length < thresholds.minRequestsForErrorRate) {
      return 0.0;
    }

    final errorCount = _recentRequests.where((final r) => r.isError).length;
    return errorCount / _recentRequests.length;
  }

  double get averageResponseTime {
    if (_recentRequests.isEmpty) return 0.0;

    final totalTime = _recentRequests.fold<double>(
      0.0,
      (final sum, final request) => sum + request.responseTimeMs,
    );
    return totalTime / _recentRequests.length;
  }

  int get requestCount => _recentRequests.length;
  int get errorCount => _recentRequests.where((final r) => r.isError).length;
  int get consecutiveFailures => _consecutiveFailures;

  void reset() {
    _recentRequests.clear();
    _consecutiveFailures = 0;
    _isDown = false;
  }

  void _cleanupOldRequests() {
    final cutoff = DateTime.now().subtract(
      Duration(milliseconds: thresholds.timeWindowMs),
    );
    _recentRequests.removeWhere(
      (final request) => request.timestamp.isBefore(cutoff),
    );
  }
}

/// Request metric for tracking
class _RequestMetric {
  const _RequestMetric({
    required this.timestamp,
    required this.responseTimeMs,
    required this.isError,
  });
  final DateTime timestamp;
  final double responseTimeMs;
  final bool isError;
}

/// Alert tracking for deduplication
class _AlertTracker {
  final Map<String, DateTime> _lastAlertTimes = <String, DateTime>{};
  final Duration _cooldownPeriod = const Duration(minutes: 5);

  bool shouldSendAlert(final AlertType type, final String providerId) {
    final key = '${type.name}_$providerId';
    final lastTime = _lastAlertTimes[key];

    if (lastTime == null) {
      _lastAlertTimes[key] = DateTime.now();
      return true;
    }

    final elapsed = DateTime.now().difference(lastTime);
    if (elapsed >= _cooldownPeriod) {
      _lastAlertTimes[key] = DateTime.now();
      return true;
    }

    return false;
  }
}

/// Provider Alert Service implementation
class ProviderAlertService implements IProviderAlertService {
  late AlertThresholds _thresholds;
  final Map<String, _ProviderHealthTracker> _healthTrackers =
      <String, _ProviderHealthTracker>{};
  final Map<AlertType, List<AlertHandler>> _typeHandlers =
      <AlertType, List<AlertHandler>>{};
  final List<AlertHandler> _globalHandlers = <AlertHandler>[];
  final Map<String, AlertFilter> _filters = <String, AlertFilter>{};
  final List<Alert> _alerts = <Alert>[];
  final _AlertTracker _alertTracker = _AlertTracker();
  final Random _random = Random();

  bool _isInitialized = false;
  bool _isEnabled = true;

  @override
  Future<void> initialize(final AlertThresholds thresholds) async {
    if (_isInitialized) {
      Log.i('Alert service already initialized');
      return;
    }

    _thresholds = thresholds;
    _isInitialized = true;

    Log.i(
      'Initialized with thresholds: '
      'responseTime=${thresholds.responseTimeThresholdMs}ms, '
      'errorRate=${(thresholds.errorRateThreshold * 100).toStringAsFixed(1)}%',
    );
  }

  @override
  void registerHandler(final AlertType type, final AlertHandler handler) {
    _typeHandlers.putIfAbsent(type, () => <AlertHandler>[]).add(handler);
    Log.d('Registered handler for ${type.name} alerts');
  }

  @override
  void registerGlobalHandler(final AlertHandler handler) {
    _globalHandlers.add(handler);
    Log.d('Registered global alert handler');
  }

  @override
  void addFilter(final String name, final AlertFilter filter) {
    _filters[name] = filter;
    Log.d('Added alert filter: $name');
  }

  @override
  void removeFilter(final String name) {
    _filters.remove(name);
    Log.d('Removed alert filter: $name');
  }

  @override
  Future<Alert> createAlert({
    required final AlertType type,
    required final AlertSeverity severity,
    required final String providerId,
    required final String title,
    required final String message,
    final double? currentValue,
    final double? threshold,
    final Map<String, dynamic> metadata = const {},
  }) async {
    if (!_isEnabled) return _createDummyAlert();

    // Check alert cooldown to prevent spam
    if (!_alertTracker.shouldSendAlert(type, providerId)) {
      Log.d('Alert cooldown active for ${type.name} on $providerId');
      return _createDummyAlert();
    }

    final alert = Alert(
      id: _generateAlertId(),
      type: type,
      severity: severity,
      providerId: providerId,
      title: title,
      message: message,
      timestamp: DateTime.now(),
      currentValue: currentValue,
      threshold: threshold,
      metadata: Map.from(metadata),
    );

    // Apply filters
    for (final filter in _filters.values) {
      if (!filter(alert)) {
        Log.d('Alert filtered out: ${alert.id}');
        return _createDummyAlert();
      }
    }

    // Store alert
    _alerts.add(alert);

    // Trigger handlers
    await _triggerHandlers(alert);

    Log.i(
      '${severity.name.toUpperCase()} alert created: $title for $providerId',
    );
    return alert;
  }

  @override
  Future<Alert> createCustomAlert({
    required final String id,
    required final String providerId,
    required final String title,
    required final String message,
    final AlertSeverity severity = AlertSeverity.warning,
    final double? currentValue,
    final double? threshold,
    final Map<String, dynamic> metadata = const {},
  }) async {
    return createAlert(
      type: AlertType.custom,
      severity: severity,
      providerId: providerId,
      title: title,
      message: message,
      currentValue: currentValue,
      threshold: threshold,
      metadata: {...metadata, 'customId': id},
    );
  }

  @override
  Future<void> resolveAlert(
    final String alertId, {
    final String? resolution,
  }) async {
    final alertIndex = _alerts.indexWhere((final alert) => alert.id == alertId);
    if (alertIndex == -1) {
      Log.w('Alert not found for resolution: $alertId');
      return;
    }

    final alert = _alerts[alertIndex];
    if (!alert.isActive) {
      Log.d('Alert already resolved: $alertId');
      return;
    }

    final resolvedAlert = alert.copyWith(
      isActive: false,
      resolvedAt: DateTime.now(),
      metadata: {
        ...alert.metadata,
        if (resolution != null) 'resolution': resolution,
      },
    );

    _alerts[alertIndex] = resolvedAlert;

    Log.i('Alert resolved: ${alert.title} for ${alert.providerId}');
  }

  @override
  Future<void> checkProviderHealth(
    final String providerId,
    final double responseTimeMs,
    final bool isError,
    final int totalRequests,
    final int errorCount,
  ) async {
    if (!_isInitialized || !_isEnabled) return;

    final tracker = _getOrCreateHealthTracker(providerId);
    tracker.recordRequest(responseTimeMs, isError);

    // Check for provider down
    if (tracker.isDown &&
        !_hasActiveAlert(AlertType.providerDown, providerId)) {
      await triggerProviderDownAlert(
        providerId,
        'Provider has ${tracker.consecutiveFailures} consecutive failures',
      );
    }

    // Check for performance degradation
    if (tracker.averageResponseTime > _thresholds.responseTimeThresholdMs &&
        !_hasActiveAlert(AlertType.performanceDegradation, providerId)) {
      await triggerPerformanceDegradationAlert(
        providerId,
        tracker.averageResponseTime,
        _thresholds.responseTimeThresholdMs.toDouble(),
      );
    }

    // Check for high error rate
    if (tracker.requestCount >= _thresholds.minRequestsForErrorRate &&
        tracker.currentErrorRate > _thresholds.errorRateThreshold &&
        !_hasActiveAlert(AlertType.highErrorRate, providerId)) {
      await triggerHighErrorRateAlert(
        providerId,
        tracker.currentErrorRate,
        _thresholds.errorRateThreshold,
      );
    }
  }

  @override
  Future<Alert> triggerProviderDownAlert(
    final String providerId,
    final String reason,
  ) async {
    return createAlert(
      type: AlertType.providerDown,
      severity: AlertSeverity.critical,
      providerId: providerId,
      title: 'Provider Down',
      message: 'Provider $providerId is unavailable: $reason',
      metadata: {'reason': reason},
    );
  }

  @override
  Future<Alert> triggerPerformanceDegradationAlert(
    final String providerId,
    final double currentResponseTime,
    final double threshold,
  ) async {
    return createAlert(
      type: AlertType.performanceDegradation,
      severity: AlertSeverity.warning,
      providerId: providerId,
      title: 'Performance Degradation',
      message:
          'Provider $providerId response time degraded to ${currentResponseTime.toStringAsFixed(0)}ms '
          '(threshold: ${threshold.toStringAsFixed(0)}ms)',
      currentValue: currentResponseTime,
      threshold: threshold,
    );
  }

  @override
  Future<Alert> triggerHighErrorRateAlert(
    final String providerId,
    final double currentErrorRate,
    final double threshold,
  ) async {
    return createAlert(
      type: AlertType.highErrorRate,
      severity: AlertSeverity.error,
      providerId: providerId,
      title: 'High Error Rate',
      message:
          'Provider $providerId error rate is ${(currentErrorRate * 100).toStringAsFixed(1)}% '
          '(threshold: ${(threshold * 100).toStringAsFixed(1)}%)',
      currentValue: currentErrorRate,
      threshold: threshold,
    );
  }

  @override
  List<Alert> getActiveAlerts() {
    return _alerts.where((final alert) => alert.isActive).toList();
  }

  @override
  List<Alert> getProviderActiveAlerts(final String providerId) {
    return _alerts
        .where(
          (final alert) => alert.isActive && alert.providerId == providerId,
        )
        .toList();
  }

  @override
  List<Alert> getAlertsBySeverity(final AlertSeverity severity) {
    return _alerts.where((final alert) => alert.severity == severity).toList();
  }

  @override
  List<Alert> getAlertsByType(final AlertType type) {
    return _alerts.where((final alert) => alert.type == type).toList();
  }

  @override
  List<Alert> getAlertHistory({
    final DateTime? startTime,
    final DateTime? endTime,
    final String? providerId,
    final AlertSeverity? severity,
    final AlertType? type,
  }) {
    return _alerts.where((final alert) {
      if (startTime != null && alert.timestamp.isBefore(startTime)) {
        return false;
      }
      if (endTime != null && alert.timestamp.isAfter(endTime)) return false;
      if (providerId != null && alert.providerId != providerId) return false;
      if (severity != null && alert.severity != severity) return false;
      if (type != null && alert.type != type) return false;
      return true;
    }).toList();
  }

  @override
  AlertStats getStats() {
    return _calculateStats(_alerts);
  }

  @override
  AlertStats getProviderStats(final String providerId) {
    final providerAlerts = _alerts
        .where((final alert) => alert.providerId == providerId)
        .toList();
    return _calculateStats(providerAlerts);
  }

  @override
  void clearOldAlerts(final Duration maxAge) {
    final cutoff = DateTime.now().subtract(maxAge);
    final initialCount = _alerts.length;

    _alerts.removeWhere(
      (final alert) =>
          !alert.isActive &&
          (alert.resolvedAt?.isBefore(cutoff) ??
              alert.timestamp.isBefore(cutoff)),
    );

    final removedCount = initialCount - _alerts.length;
    if (removedCount > 0) {
      Log.i('Cleared $removedCount old alerts');
    }
  }

  @override
  void setEnabled(final bool enabled) {
    _isEnabled = enabled;
    Log.i('Alerting ${enabled ? "enabled" : "disabled"}');
  }

  @override
  bool get isEnabled => _isEnabled;

  // Private helper methods

  _ProviderHealthTracker _getOrCreateHealthTracker(final String providerId) {
    return _healthTrackers.putIfAbsent(
      providerId,
      () => _ProviderHealthTracker(providerId, _thresholds),
    );
  }

  bool _hasActiveAlert(final AlertType type, final String providerId) {
    return _alerts.any(
      (final alert) =>
          alert.isActive &&
          alert.type == type &&
          alert.providerId == providerId,
    );
  }

  String _generateAlertId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = _random.nextInt(10000).toString().padLeft(4, '0');
    return 'alert_${timestamp}_$randomSuffix';
  }

  Alert _createDummyAlert() {
    return Alert(
      id: 'dummy',
      type: AlertType.custom,
      severity: AlertSeverity.info,
      providerId: 'dummy',
      title: 'Dummy Alert',
      message: 'This alert was filtered or throttled',
      timestamp: DateTime.now(),
      isActive: false,
    );
  }

  Future<void> _triggerHandlers(final Alert alert) async {
    // Trigger type-specific handlers
    final typeHandlers = _typeHandlers[alert.type] ?? <AlertHandler>[];
    for (final handler in typeHandlers) {
      try {
        handler(alert);
      } on Object catch (e) {
        Log.e('Error in type handler for ${alert.type.name}: $e');
      }
    }

    // Trigger global handlers
    for (final handler in _globalHandlers) {
      try {
        handler(alert);
      } on Object catch (e) {
        Log.e('Error in global handler: $e');
      }
    }
  }

  AlertStats _calculateStats(final List<Alert> alerts) {
    if (alerts.isEmpty) {
      return const AlertStats(
        totalAlerts: 0,
        alertsBySeverity: {},
        alertsByType: {},
        alertsByProvider: {},
        activeAlerts: 0,
        resolvedAlerts: 0,
        averageResolutionTimeMs: 0.0,
        alertFrequency: 0.0,
      );
    }

    final severityCount = <AlertSeverity, int>{};
    final typeCount = <AlertType, int>{};
    final providerCount = <String, int>{};
    int activeCount = 0;
    int resolvedCount = 0;
    double totalResolutionTime = 0.0;

    for (final alert in alerts) {
      severityCount[alert.severity] = (severityCount[alert.severity] ?? 0) + 1;
      typeCount[alert.type] = (typeCount[alert.type] ?? 0) + 1;
      providerCount[alert.providerId] =
          (providerCount[alert.providerId] ?? 0) + 1;

      if (alert.isActive) {
        activeCount++;
      } else {
        resolvedCount++;
        if (alert.resolvedAt != null) {
          totalResolutionTime += alert.resolvedAt!
              .difference(alert.timestamp)
              .inMilliseconds;
        }
      }
    }

    final averageResolutionTime = resolvedCount > 0
        ? totalResolutionTime / resolvedCount
        : 0.0;

    // Calculate alert frequency (alerts per hour in last 24 hours)
    final last24Hours = DateTime.now().subtract(const Duration(hours: 24));
    final recentAlerts = alerts
        .where((final alert) => alert.timestamp.isAfter(last24Hours))
        .length;
    const hoursInDay = 24.0;
    final alertFrequency = recentAlerts / hoursInDay;

    return AlertStats(
      totalAlerts: alerts.length,
      alertsBySeverity: severityCount,
      alertsByType: typeCount,
      alertsByProvider: providerCount,
      activeAlerts: activeCount,
      resolvedAlerts: resolvedCount,
      averageResolutionTimeMs: averageResolutionTime,
      alertFrequency: alertFrequency,
    );
  }
}
