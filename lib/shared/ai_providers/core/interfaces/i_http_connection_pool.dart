/// HTTP Connection Pool interface for optimized network communication
///
/// Provides connection pooling, keep-alive, and performance optimization
/// for AI provider HTTP requests.
library;

import 'dart:io';

/// HTTP connection pool configuration
class ConnectionPoolConfig {
  const ConnectionPoolConfig({
    this.maxConnectionsPerHost = 10,
    this.maxTotalConnections = 50,
    this.connectionTimeoutMs = 30000,
    this.keepAliveTimeoutMs = 60000,
    this.maxIdleTimeMs = 300000, // 5 minutes
    this.enableHttp2 = true,
    this.enableCompression = true,
  });

  /// Maximum number of connections per host
  final int maxConnectionsPerHost;

  /// Maximum total connections across all hosts
  final int maxTotalConnections;

  /// Connection timeout in milliseconds
  final int connectionTimeoutMs;

  /// Keep-alive timeout in milliseconds
  final int keepAliveTimeoutMs;

  /// Maximum idle time before closing connection
  final int maxIdleTimeMs;

  /// Enable HTTP/2 if available
  final bool enableHttp2;

  /// Enable request/response compression
  final bool enableCompression;
}

/// Connection statistics for monitoring
class ConnectionStats {
  const ConnectionStats({
    required this.activeConnections,
    required this.idleConnections,
    required this.totalRequests,
    required this.cacheHits,
    required this.cacheMisses,
    required this.averageReuseCount,
    required this.totalBytesTransferred,
    required this.averageRequestTimeMs,
  });

  /// Total active connections
  final int activeConnections;

  /// Total idle connections
  final int idleConnections;

  /// Total requests served
  final int totalRequests;

  /// Connection cache hits
  final int cacheHits;

  /// Connection cache misses
  final int cacheMisses;

  /// Average connection reuse count
  final double averageReuseCount;

  /// Bytes transferred (uploaded + downloaded)
  final int totalBytesTransferred;

  /// Average request time in milliseconds
  final double averageRequestTimeMs;

  /// Cache hit ratio (0.0 - 1.0)
  double get cacheHitRatio {
    final total = cacheHits + cacheMisses;
    return total > 0 ? cacheHits / total : 0.0;
  }
}

/// HTTP Connection Pool interface
abstract class IHttpConnectionPool {
  /// Initialize the connection pool with configuration
  Future<void> initialize(final ConnectionPoolConfig config);

  /// Get or create an HTTP client for the specified host
  ///
  /// Returns a configured HttpClient with connection pooling,
  /// keep-alive, and performance optimizations enabled.
  Future<HttpClient> getClient(final String host);

  /// Release a client back to the pool
  ///
  /// Allows the pool to manage connection lifecycle and reuse.
  Future<void> releaseClient(final String host, final HttpClient client);

  /// Get connection statistics for monitoring
  ConnectionStats getStats();

  /// Get host-specific statistics
  ConnectionStats getHostStats(final String host);

  /// Clean up idle connections
  Future<void> cleanupIdleConnections();

  /// Close all connections and shutdown pool
  Future<void> shutdown();

  /// Enable/disable compression for all connections
  void setCompressionEnabled(final bool enabled);

  /// Set custom headers for all requests
  void setDefaultHeaders(final Map<String, String> headers);

  /// Configure proxy settings
  void setProxy(
    final String proxyHost,
    final int proxyPort, {
    final String? username,
    final String? password,
  });
}
