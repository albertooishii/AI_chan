/// Request deduplication service to prevent duplicate concurrent calls
/// and optimize API usage by caching in-flight requests.
library;

import 'dart:async';
import 'dart:convert';

import 'package:ai_chan/core/models/ai_response.dart';
import 'package:ai_chan/core/models/system_prompt.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Request fingerprint for deduplication
class RequestFingerprint {
  const RequestFingerprint({
    required this.hash,
    required this.providerId,
    required this.model,
    required this.capability,
    this.metadata = const {},
  });

  final String hash;
  final String providerId;
  final String model;
  final String capability;
  final Map<String, dynamic> metadata;

  @override
  String toString() => hash;

  @override
  bool operator ==(final Object other) {
    return other is RequestFingerprint && other.hash == hash;
  }

  @override
  int get hashCode => hash.hashCode;
}

/// In-flight request tracker
class InFlightRequest {
  InFlightRequest({
    required this.fingerprint,
    required this.future,
    required this.startTime,
  });

  final RequestFingerprint fingerprint;
  final Future<AIResponse> future;
  final DateTime startTime;

  bool get isExpired {
    return DateTime.now().difference(startTime) > const Duration(minutes: 5);
  }
}

/// Request deduplication service
class RequestDeduplicationService {
  factory RequestDeduplicationService() => _instance;
  RequestDeduplicationService._internal() {
    _startCleanupTimer();
  }
  static final RequestDeduplicationService _instance =
      RequestDeduplicationService._internal();

  final Map<String, InFlightRequest> _inFlightRequests = {};
  Timer? _cleanupTimer;

  // Statistics
  int _totalRequests = 0;
  int _deduplicatedRequests = 0;

  /// Create a fingerprint for a request
  RequestFingerprint createFingerprint({
    required final String providerId,
    required final String model,
    required final String capability,
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) {
    // Create a deterministic hash of the request
    final requestData = {
      'provider': providerId,
      'model': model,
      'capability': capability,
      'history': history,
      'system_prompt': {
        'instructions': systemPrompt.instructions,
        'profile': {
          'user_name': systemPrompt.profile.userName,
          'ai_name': systemPrompt.profile.aiName,
          // Don't include date/time for fingerprinting as it changes constantly
        },
      },
      'image_base64': imageBase64?.substring(0, 100), // First 100 chars only
      'image_mime_type': imageMimeType,
      'additional_params': additionalParams,
    };

    final jsonString = json.encode(requestData);
    final hash = jsonString.hashCode.toString();

    return RequestFingerprint(
      hash: hash,
      providerId: providerId,
      model: model,
      capability: capability,
      metadata: {
        'created_at': DateTime.now().toIso8601String(),
        'history_length': history.length,
        'has_image': imageBase64 != null,
      },
    );
  }

  /// Get or create a request, handling deduplication
  Future<AIResponse> getOrCreateRequest(
    final RequestFingerprint fingerprint,
    final Future<AIResponse> Function() requestFactory,
  ) async {
    _totalRequests++;

    // Check if we already have this request in flight
    final existing = _inFlightRequests[fingerprint.hash];
    if (existing != null && !existing.isExpired) {
      _deduplicatedRequests++;
      Log.d(
        '[Dedup] Found duplicate request: ${fingerprint.hash.substring(0, 8)}...',
      );
      return existing.future;
    }

    // Remove expired request if it exists
    if (existing?.isExpired == true) {
      _inFlightRequests.remove(fingerprint.hash);
    }

    Log.d(
      '[Dedup] Creating new request: ${fingerprint.hash.substring(0, 8)}...',
    );

    // Create new request
    final completer = Completer<AIResponse>();
    final inFlightRequest = InFlightRequest(
      fingerprint: fingerprint,
      future: completer.future,
      startTime: DateTime.now(),
    );

    _inFlightRequests[fingerprint.hash] = inFlightRequest;

    // Execute the request
    try {
      final response = await requestFactory();
      completer.complete(response);

      // Remove from in-flight after completion
      _inFlightRequests.remove(fingerprint.hash);

      return response;
    } catch (e) {
      completer.completeError(e);

      // Remove from in-flight after error
      _inFlightRequests.remove(fingerprint.hash);

      rethrow;
    }
  }

  /// Get deduplication statistics
  Map<String, dynamic> getStats() {
    final deduplicationRate = _totalRequests > 0
        ? _deduplicatedRequests / _totalRequests
        : 0.0;

    return {
      'total_requests': _totalRequests,
      'deduplicated_requests': _deduplicatedRequests,
      'deduplication_rate': deduplicationRate,
      'in_flight_requests': _inFlightRequests.length,
      'memory_usage_estimate': _estimateMemoryUsage(),
    };
  }

  /// Clear all in-flight requests
  void clearInFlightRequests() {
    final count = _inFlightRequests.length;
    _inFlightRequests.clear();
    Log.i('[Dedup] Cleared $count in-flight requests');
  }

  /// Reset statistics
  void resetStats() {
    _totalRequests = 0;
    _deduplicatedRequests = 0;
    Log.i('[Dedup] Reset statistics');
  }

  /// Get current in-flight requests info
  List<Map<String, dynamic>> getInFlightRequestsInfo() {
    return _inFlightRequests.values.map((final request) {
      return {
        'hash': request.fingerprint.hash.substring(0, 8),
        'provider_id': request.fingerprint.providerId,
        'model': request.fingerprint.model,
        'capability': request.fingerprint.capability,
        'age_seconds': DateTime.now().difference(request.startTime).inSeconds,
        'metadata': request.fingerprint.metadata,
      };
    }).toList();
  }

  /// Start periodic cleanup of expired requests
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanupExpiredRequests();
    });
  }

  /// Clean up expired in-flight requests
  void _cleanupExpiredRequests() {
    final keysToRemove = <String>[];

    for (final entry in _inFlightRequests.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _inFlightRequests.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      Log.d('[Dedup] Cleaned up ${keysToRemove.length} expired requests');
    }
  }

  /// Estimate memory usage
  int _estimateMemoryUsage() {
    int totalBytes = 0;

    for (final entry in _inFlightRequests.entries) {
      totalBytes += entry.key.length * 2; // Hash string
      totalBytes += 200; // Request object overhead
    }

    return totalBytes;
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _inFlightRequests.clear();
    Log.d('[Dedup] Disposed deduplication service');
  }
}
