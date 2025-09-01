import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';

void main() {
  group('Google Backup Android Diagnostics', () {
    setUp(() {
      // Reset circuit breaker before each test
      GoogleBackupService.resetCircuitBreakerForTesting();
    });

    test('should return circuit breaker status with initial values', () async {
      final status = GoogleBackupService.getCircuitBreakerStatus();

      expect(status['failures'], 0);
      expect(status['maxFailures'], 8);
      expect(status['isActive'], false);
      expect(status['cooldownMinutes'], 15);
      expect(status['lastFailure'], null);
      expect(status.containsKey('cooldownRemainingSeconds'), false);
    });

    test(
      'should track circuit breaker activation after max failures',
      () async {
        // Simulate multiple failures to trigger circuit breaker
        for (int i = 0; i < 8; i++) {
          GoogleBackupService.recordOAuthFailure('test failure $i');
        }

        final status = GoogleBackupService.getCircuitBreakerStatus();

        expect(status['failures'], 8);
        expect(status['isActive'], true);
        expect(status['lastFailure'], isNotNull);
        expect(status['cooldownRemainingSeconds'], greaterThanOrEqualTo(0));
      },
    );

    test('should provide comprehensive Android session diagnosis', () async {
      final diagnosis =
          await GoogleBackupService.diagnoseAndroidSessionIssues();

      // Check basic structure
      expect(diagnosis, isA<Map<String, dynamic>>());
      expect(diagnosis['timestamp'], isNotNull);
      expect(diagnosis['circuitBreaker'], isA<Map<String, dynamic>>());

      // Platform detection (in test environment, it's typically not Android)
      expect(diagnosis.containsKey('platform'), true);

      // In test environment, credential checking fails due to missing Flutter bindings
      // So we expect a credentialCheckError instead of hasStoredCredentials
      expect(diagnosis.containsKey('credentialCheckError'), true);
    });

    test('should handle diagnostic errors gracefully', () async {
      // This test ensures the diagnostic method doesn't crash even if internal operations fail
      final diagnosis =
          await GoogleBackupService.diagnoseAndroidSessionIssues();

      // Should always return a map, even if some checks fail
      expect(diagnosis, isA<Map<String, dynamic>>());
      expect(diagnosis['timestamp'], isNotNull);
    });

    test('should calculate cooldown remaining time correctly', () async {
      // Trigger circuit breaker
      for (int i = 0; i < 8; i++) {
        GoogleBackupService.recordOAuthFailure('test failure $i');
      }

      final status1 = GoogleBackupService.getCircuitBreakerStatus();
      expect(status1['isActive'], true);
      expect(
        status1['cooldownRemainingSeconds'],
        greaterThan(14 * 60),
      ); // Should be close to 15 minutes

      // Wait a second and check again
      await Future.delayed(const Duration(milliseconds: 100));

      final status2 = GoogleBackupService.getCircuitBreakerStatus();
      expect(
        status2['cooldownRemainingSeconds'],
        lessThanOrEqualTo(status1['cooldownRemainingSeconds']),
      );
    });
  });
}
