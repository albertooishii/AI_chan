/// Provider Alert System interface for proactive monitoring
///
/// Provides real-time alerts for provider failures, performance degradation,
/// and capacity issues to enable proactive system management.
library;

/// Alert severity levels
enum AlertSeverity {
  /// Informational alerts - system events
  info,

  /// Warning alerts - potential issues
  warning,

  /// Error alerts - service degradation
  error,

  /// Critical alerts - service outages
  critical,
}

/// Alert types for different monitoring scenarios
enum AlertType {
  /// Provider is completely unavailable
  providerDown,

  /// Provider response time degraded
  performanceDegradation,

  /// Provider error rate exceeds threshold
  highErrorRate,

  /// Provider approaching rate limits
  rateLimitWarning,

  /// Circuit breaker opened
  circuitBreakerOpen,

  /// Provider capacity issues
  capacityLimit,

  /// Configuration errors
  configurationError,

  /// Authentication failures
  authenticationFailure,

  /// Custom provider-specific alerts
  custom,
}

/// Alert configuration thresholds
class AlertThresholds {
  const AlertThresholds({
    this.responseTimeThresholdMs = 10000, // 10 seconds
    this.errorRateThreshold = 0.1, // 10%
    this.minRequestsForErrorRate = 10,
    this.timeWindowMs = 300000, // 5 minutes
    this.rateLimitWarningThreshold = 0.8, // 80% of limit
    this.unavailabilityThreshold = 5,
    this.capacityWarningThreshold = 0.9, // 90% capacity
  });

  /// Response time threshold in milliseconds
  final int responseTimeThresholdMs;

  /// Error rate threshold (0.0 - 1.0)
  final double errorRateThreshold;

  /// Minimum requests for error rate calculation
  final int minRequestsForErrorRate;

  /// Time window for calculations in milliseconds
  final int timeWindowMs;

  /// Rate limit warning threshold (0.0 - 1.0)
  final double rateLimitWarningThreshold;

  /// Provider unavailability threshold (consecutive failures)
  final int unavailabilityThreshold;

  /// Capacity warning threshold (0.0 - 1.0)
  final double capacityWarningThreshold;
}

/// Alert information
class Alert {
  const Alert({
    required this.id,
    required this.type,
    required this.severity,
    required this.providerId,
    required this.title,
    required this.message,
    required this.timestamp,
    this.currentValue,
    this.threshold,
    this.metadata = const {},
    this.isActive = true,
    this.resolvedAt,
  });

  /// Unique alert identifier
  final String id;

  /// Alert type
  final AlertType type;

  /// Alert severity
  final AlertSeverity severity;

  /// Provider identifier that triggered the alert
  final String providerId;

  /// Alert title
  final String title;

  /// Detailed alert message
  final String message;

  /// Timestamp when alert was created
  final DateTime timestamp;

  /// Current metric value that triggered the alert
  final double? currentValue;

  /// Threshold value that was exceeded
  final double? threshold;

  /// Additional metadata
  final Map<String, dynamic> metadata;

  /// Whether the alert is still active
  final bool isActive;

  /// When the alert was resolved (if resolved)
  final DateTime? resolvedAt;

  /// Create a copy with updated fields
  Alert copyWith({
    final bool? isActive,
    final DateTime? resolvedAt,
    final Map<String, dynamic>? metadata,
  }) {
    return Alert(
      id: id,
      type: type,
      severity: severity,
      providerId: providerId,
      title: title,
      message: message,
      timestamp: timestamp,
      currentValue: currentValue,
      threshold: threshold,
      metadata: metadata ?? this.metadata,
      isActive: isActive ?? this.isActive,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}

/// Alert handler callback function
typedef AlertHandler = void Function(Alert alert);

/// Alert filter function
typedef AlertFilter = bool Function(Alert alert);

/// Alert statistics
class AlertStats {
  const AlertStats({
    required this.totalAlerts,
    required this.alertsBySeverity,
    required this.alertsByType,
    required this.alertsByProvider,
    required this.activeAlerts,
    required this.resolvedAlerts,
    required this.averageResolutionTimeMs,
    required this.alertFrequency,
  });

  /// Total alerts created
  final int totalAlerts;

  /// Alerts by severity
  final Map<AlertSeverity, int> alertsBySeverity;

  /// Alerts by type
  final Map<AlertType, int> alertsByType;

  /// Alerts by provider
  final Map<String, int> alertsByProvider;

  /// Currently active alerts
  final int activeAlerts;

  /// Resolved alerts
  final int resolvedAlerts;

  /// Average time to resolution in milliseconds
  final double averageResolutionTimeMs;

  /// Alert frequency (alerts per hour)
  final double alertFrequency;
}

/// Provider Alert Service interface
abstract class IProviderAlertService {
  /// Initialize the alert service with configuration
  Future<void> initialize(final AlertThresholds thresholds);

  /// Register an alert handler for specific alert types
  void registerHandler(final AlertType type, final AlertHandler handler);

  /// Register a global alert handler for all alerts
  void registerGlobalHandler(final AlertHandler handler);

  /// Add a custom alert filter
  void addFilter(final String name, final AlertFilter filter);

  /// Remove an alert filter
  void removeFilter(final String name);

  /// Create and trigger a new alert
  Future<Alert> createAlert({
    required final AlertType type,
    required final AlertSeverity severity,
    required final String providerId,
    required final String title,
    required final String message,
    final double? currentValue,
    final double? threshold,
    final Map<String, dynamic> metadata = const {},
  });

  /// Create a custom alert with specific ID
  Future<Alert> createCustomAlert({
    required final String id,
    required final String providerId,
    required final String title,
    required final String message,
    final AlertSeverity severity = AlertSeverity.warning,
    final double? currentValue,
    final double? threshold,
    final Map<String, dynamic> metadata = const {},
  });

  /// Resolve an active alert
  Future<void> resolveAlert(final String alertId, {final String? resolution});

  /// Check provider metrics and trigger alerts if thresholds exceeded
  Future<void> checkProviderHealth(
    final String providerId,
    final double responseTimeMs,
    final bool isError,
    final int totalRequests,
    final int errorCount,
  );

  /// Manually trigger a provider down alert
  Future<Alert> triggerProviderDownAlert(
    final String providerId,
    final String reason,
  );

  /// Manually trigger a performance degradation alert
  Future<Alert> triggerPerformanceDegradationAlert(
    final String providerId,
    final double currentResponseTime,
    final double threshold,
  );

  /// Manually trigger a high error rate alert
  Future<Alert> triggerHighErrorRateAlert(
    final String providerId,
    final double currentErrorRate,
    final double threshold,
  );

  /// Get all active alerts
  List<Alert> getActiveAlerts();

  /// Get active alerts for a specific provider
  List<Alert> getProviderActiveAlerts(final String providerId);

  /// Get alerts by severity
  List<Alert> getAlertsBySeverity(final AlertSeverity severity);

  /// Get alerts by type
  List<Alert> getAlertsByType(final AlertType type);

  /// Get alert history within time range
  List<Alert> getAlertHistory({
    final DateTime? startTime,
    final DateTime? endTime,
    final String? providerId,
    final AlertSeverity? severity,
    final AlertType? type,
  });

  /// Get alert statistics
  AlertStats getStats();

  /// Get provider-specific alert statistics
  AlertStats getProviderStats(final String providerId);

  /// Clear resolved alerts older than specified duration
  void clearOldAlerts(final Duration maxAge);

  /// Enable/disable alerting
  void setEnabled(final bool enabled);

  /// Check if alerting is enabled
  bool get isEnabled;
}
