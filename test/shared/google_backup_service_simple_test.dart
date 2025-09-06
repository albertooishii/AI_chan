import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleBackupService - Basic Functionality', () {
    setUp(() async {
      // Reset circuit breaker state before each test
      GoogleBackupService.resetCircuitBreakerForTest();
    });

    group('☁️ Drive Upload Tests', () {
      test('should upload backup with resumable upload - Happy Path', () async {
        final client = MockClient((final request) async {
          final url = request.url.toString();

          // Mock resumable upload initiation
          if (url.contains('/upload') &&
              request.method == 'POST' &&
              request.headers['X-Upload-Content-Type'] == 'application/zip') {
            return http.Response(
              '{}',
              200,
              headers: {
                'location': 'https://upload.example.com/session/abc123',
              },
            );
          }

          // Mock resumable upload PUT
          if (url.contains('upload.example.com') && request.method == 'PUT') {
            return http.Response(
              jsonEncode({
                'id': 'backup_file_123',
                'name': 'ai_chan_backup.zip',
              }),
              200,
            );
          }

          return http.Response('not found', 404);
        });

        // Create test backup file
        final tmpDir = Directory.systemTemp.createTempSync('backup_test_');
        final backupFile = File('${tmpDir.path}/test_backup.zip');
        await backupFile.writeAsBytes([80, 75, 3, 4]); // ZIP magic bytes

        final service = GoogleBackupService(
          accessToken: 'valid_access_token',
          httpClient: client,
        );

        final fileId = await service.uploadBackupResumable(backupFile);
        expect(fileId, equals('backup_file_123'));

        // Cleanup
        await tmpDir.delete(recursive: true);
      });

      test('should handle network failures gracefully', () async {
        final networkFailureClient = MockClient((final request) async {
          throw const SocketException('Network unreachable');
        });

        final tmpDir = Directory.systemTemp.createTempSync('network_test_');
        final backupFile = File('${tmpDir.path}/network_test.zip');
        await backupFile.writeAsBytes([80, 75, 3, 4]);

        final service = GoogleBackupService(
          accessToken: 'valid_token',
          httpClient: networkFailureClient,
        );

        expect(
          () => service.uploadBackupResumable(backupFile),
          throwsA(isA<SocketException>()),
        );

        await tmpDir.delete(recursive: true);
      });

      test('should handle HTTP errors during upload', () async {
        final errorClient = MockClient((final request) async {
          return http.Response('Internal Server Error', 500);
        });

        final tmpDir = Directory.systemTemp.createTempSync('error_test_');
        final backupFile = File('${tmpDir.path}/error_test.zip');
        await backupFile.writeAsBytes([80, 75, 3, 4]);

        final service = GoogleBackupService(
          accessToken: 'valid_token',
          httpClient: errorClient,
        );

        expect(
          () => service.uploadBackupResumable(backupFile),
          throwsA(isA<HttpException>()),
        );

        await tmpDir.delete(recursive: true);
      });
    });

    group('📋 List Backups Tests', () {
      test('should list existing backups', () async {
        final client = MockClient((final request) async {
          final url = request.url.toString();

          if (url.contains('/drive/v3/files') && request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 'backup1',
                    'name': 'ai_chan_backup.zip',
                    'createdTime': '2025-01-30T10:00:00Z',
                    'modifiedTime': '2025-01-30T10:00:00Z',
                    'size': '1024000',
                  },
                  {
                    'id': 'backup2',
                    'name': 'ai_chan_backup.zip',
                    'createdTime': '2025-01-29T10:00:00Z',
                    'modifiedTime': '2025-01-29T10:00:00Z',
                    'size': '512000',
                  },
                ],
              }),
              200,
            );
          }

          return http.Response('not found', 404);
        });

        final service = GoogleBackupService(
          accessToken: 'valid_access_token',
          httpClient: client,
        );

        final backups = await service.listBackups();
        expect(backups.length, equals(2));
        expect(backups[0]['id'], equals('backup1'));
        expect(backups[1]['id'], equals('backup2'));
      });

      test('should handle empty backup list', () async {
        final client = MockClient((final request) async {
          final url = request.url.toString();

          if (url.contains('/drive/v3/files') && request.method == 'GET') {
            return http.Response(jsonEncode({'files': []}), 200);
          }

          return http.Response('not found', 404);
        });

        final service = GoogleBackupService(
          accessToken: 'valid_access_token',
          httpClient: client,
        );

        final backups = await service.listBackups();
        expect(backups.length, equals(0));
      });
    });

    group('🗑️ Delete Backup Tests', () {
      test('should delete backup file successfully', () async {
        final client = MockClient((final request) async {
          if (request.method == 'DELETE' &&
              request.url.toString().contains(
                '/drive/v3/files/backup_to_delete',
              )) {
            return http.Response('{}', 200);
          }
          return http.Response('not found', 404);
        });

        final service = GoogleBackupService(
          accessToken: 'valid_token',
          httpClient: client,
        );

        // Should complete without throwing
        await service.deleteBackup('backup_to_delete');
      });

      test('should handle delete errors', () async {
        final client = MockClient((final request) async {
          if (request.method == 'DELETE') {
            return http.Response('Not Found', 404);
          }
          return http.Response('not found', 404);
        });

        final service = GoogleBackupService(
          accessToken: 'valid_token',
          httpClient: client,
        );

        expect(
          () => service.deleteBackup('non_existent_backup'),
          throwsA(isA<HttpException>()),
        );
      });
    });

    group('🔄 OAuth Token Test - Without Storage', () {
      test('should create service with access token', () {
        final service = GoogleBackupService(accessToken: 'test_access_token');

        // Verify service was created successfully
        expect(service.accessToken, equals('test_access_token'));
      });

      test('should handle missing access token', () {
        final service = GoogleBackupService(accessToken: null);

        // Verify service was created even without token
        expect(service.accessToken, isNull);
      });
    });

    group('🚨 Circuit Breaker Tests', () {
      test('should reset circuit breaker for testing', () {
        // Test the helper method exists and can be called
        expect(
          () => GoogleBackupService.resetCircuitBreakerForTest(),
          returnsNormally,
        );
      });

      test('should call force unlink for testing', () async {
        // Test the helper method exists and can be called
        expect(() => GoogleBackupService.forceUnlinkForTest(), returnsNormally);
      });
    });
  });
}
