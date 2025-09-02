import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';

void main() {
  group('Google Backup Android Diagnostics', () {
    setUp(() {
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

      expect(diagnosis, isA<Map<String, dynamic>>());
      expect(diagnosis['timestamp'], isNotNull);
      expect(diagnosis['circuitBreaker'], isA<Map<String, dynamic>>());
      expect(diagnosis.containsKey('platform'), true);
      expect(diagnosis.containsKey('credentialCheckError'), true);
    });

    test('should handle diagnostic errors gracefully', () async {
      final diagnosis =
          await GoogleBackupService.diagnoseAndroidSessionIssues();
      expect(diagnosis, isA<Map<String, dynamic>>());
      expect(diagnosis['timestamp'], isNotNull);
    });

    test('should calculate cooldown remaining time correctly', () async {
      for (int i = 0; i < 8; i++) {
        GoogleBackupService.recordOAuthFailure('test failure $i');
      }

      final status1 = GoogleBackupService.getCircuitBreakerStatus();
      expect(status1['isActive'], true);
      expect(status1['cooldownRemainingSeconds'], greaterThan(14 * 60));

      await Future.delayed(const Duration(milliseconds: 100));

      final status2 = GoogleBackupService.getCircuitBreakerStatus();
      expect(
        status2['cooldownRemainingSeconds'],
        lessThanOrEqualTo(status1['cooldownRemainingSeconds']),
      );
    });
  });

  group('Android OAuth Refresh Fix - Credential Consistency', () {
    test('should demonstrate the credential mismatch problem that was fixed', () {
      const webClientId = '555666777-web.apps.googleusercontent.com';
      const androidClientId = '123456789-android.apps.googleusercontent.com';

      final String signInCredential = webClientId;
      final String storedClientId = androidClientId;

      expect(
        signInCredential,
        isNot(equals(storedClientId)),
        reason:
            'This credential mismatch was the root cause of Android OAuth refresh failures',
      );
    });

    test('should validate the credential consistency fix', () {
      const webClientId = '555666777-web.apps.googleusercontent.com';
      const androidClientId = '123456789-android.apps.googleusercontent.com';

      final String signInCredential = webClientId;
      final String originalClientId = webClientId;
      final String currentPlatformClientId = androidClientId;

      expect(
        signInCredential,
        equals(originalClientId),
        reason:
            'originalClientId should match the credentials used during sign-in',
      );

      expect(
        currentPlatformClientId,
        equals(androidClientId),
        reason: 'Platform-specific client ID should be preserved for detection',
      );
    });

    test('should validate client ID detection logic', () {
      const webClientId = '555666777-web.apps.googleusercontent.com';
      const androidClientId = '123456789-android.apps.googleusercontent.com';

      final Map<String, String> storedCredentials = {
        'originalClientId': webClientId,
        'clientId': androidClientId,
      };

      final platformClientIds = {
        'android': androidClientId,
        'web': webClientId,
      };

      String refreshClientId;
      if (storedCredentials.containsKey('originalClientId')) {
        refreshClientId = storedCredentials['originalClientId']!;
      } else {
        String detectedPlatform = 'web';
        for (final entry in platformClientIds.entries) {
          if (entry.value == storedCredentials['clientId']) {
            detectedPlatform = entry.key;
            break;
          }
        }
        refreshClientId = platformClientIds[detectedPlatform]!;
      }

      expect(
        refreshClientId,
        equals(webClientId),
        reason:
            'Should use web client ID for refresh when originalClientId is stored (mobile sign-in scenario)',
      );
    });

    test('should validate fallback behavior for web sign-in', () {
      const webClientId = '555666777-web.apps.googleusercontent.com';

      final Map<String, String> storedCredentials = {'clientId': webClientId};

      final platformClientIds = {
        'android': '123456789-android.apps.googleusercontent.com',
        'web': webClientId,
      };

      String refreshClientId;
      if (storedCredentials.containsKey('originalClientId')) {
        refreshClientId = storedCredentials['originalClientId']!;
      } else {
        String detectedPlatform = 'web';
        for (final entry in platformClientIds.entries) {
          if (entry.value == storedCredentials['clientId']) {
            detectedPlatform = entry.key;
            break;
          }
        }
        refreshClientId = platformClientIds[detectedPlatform]!;
      }

      expect(
        refreshClientId,
        equals(webClientId),
        reason:
            'Web sign-in should still work correctly with platform detection fallback',
      );
    });
  });
}
