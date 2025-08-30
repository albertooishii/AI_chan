import 'dart:async';
import 'dart:io';

import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

// ------------------ Test hooks types (top-level) ------------------
typedef LocalBackupCreator = Future<File> Function({required String jsonStr, String? destinationDirPath});
typedef GoogleBackupServiceFactory = GoogleBackupService Function();
typedef GoogleTokenLoaderFactory = GoogleBackupService Function();

/// Helper minimal para subir backups automáticamente cuando se complete
/// un resumen de bloque. Esta implementación es "fire and forget": intenta
/// crear el ZIP local y subirlo si la cuenta Google está vinculada.
class BackupAutoUploader {
  /// Attempt to upload a backup if `googleLinked` is true. This method
  /// performs non-blocking work and returns when the attempt has been
  /// scheduled/completed. Errors are caught and logged but not rethrown.
  static Future<void> maybeUploadAfterSummary({
    required AiChanProfile profile,
    required List<Message> messages,
    required List<TimelineEntry> timeline,
    required bool googleLinked,
    dynamic repository,
  }) async {
    if (!googleLinked) return;
    // Simple in-memory coalescing to avoid repeated uploads in quick bursts.
    // This is process-local and resets on app restart.
    const coalesceSeconds = 60;
    _lastAttempt ??= 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastSuccess != null && (nowMs - _lastSuccess!) < (coalesceSeconds * 1000)) return;
    if ((nowMs - (_lastAttempt ?? 0)) < 1000) return; // avoid multiple immediate calls
    _lastAttempt = nowMs;
    try {
      Log.i('Automatic backup: triggered; preparing export JSON...', tag: 'BACKUP_AUTO');
      // Build export JSON from profile/messages/events (null events here)
      final jsonStr = await BackupUtils.exportChatPartsToJson(
        profile: profile,
        messages: messages,
        events: [],
        repository: repository,
      );
      // Create the tmp dir where the ZIP would be placed. We will try to
      // ensure we have a usable access token before creating the potentially
      // costly ZIP and attempting the upload. Tests that inject a
      // `testGoogleBackupServiceFactory` are trusted to provide a working
      // service and therefore skip the stored-token check.
      final tmpDir = Directory.systemTemp.createTempSync('ai_chan_backup_');

      final bool skipTokenCheck = testGoogleBackupServiceFactory != null;
      GoogleBackupService svc;
      if (!skipTokenCheck) {
        // Use a lightweight service instance to read stored access token or
        // credentials. Allow tests to inject a token-loader for deterministic
        // behavior.
        final tokenLoader = testTokenLoaderFactory != null
            ? testTokenLoaderFactory!()
            : GoogleBackupService(accessToken: null);

        var storedToken = await tokenLoader.loadStoredAccessToken();
        if (storedToken == null || storedToken.isEmpty) {
          // Attempt to load full stored credentials to check for a refresh_token.
          try {
            final creds = await tokenLoader.loadStoredCredentials();
            final refreshToken = creds?['refresh_token'] as String?;
            if (refreshToken != null && refreshToken.isNotEmpty) {
              // Try to refresh using configured client id/secret via public API.
              try {
                final cid = await GoogleBackupService.resolveClientId('');
                final csecret = await GoogleBackupService.resolveClientSecret();
                if (cid.isNotEmpty) {
                  final refreshed = await tokenLoader.refreshAccessToken(clientId: cid, clientSecret: csecret);
                  final newAccess = refreshed['access_token'] as String?;
                  if (newAccess != null && newAccess.isNotEmpty) {
                    storedToken = newAccess;
                  }
                } else {
                  Log.w('Automatic backup: no client id configured for refresh', tag: 'BACKUP_AUTO');
                }
              } catch (e) {
                Log.w('Automatic backup: refresh attempt failed: $e', tag: 'BACKUP_AUTO');
              }
            }
          } catch (e) {
            Log.w('Automatic backup: failed loading stored credentials: $e', tag: 'BACKUP_AUTO');
          }
        }

        if (storedToken == null || storedToken.isEmpty) {
          Log.w('Automatic backup: no stored access token available; skipping upload', tag: 'BACKUP_AUTO');
          // Clean up the temp dir we created and exit early.
          try {
            if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
          } catch (e) {
            Log.w('Automatic backup: failed deleting temp dir during early abort: $e', tag: 'BACKUP_AUTO');
          }
          return;
        }
        svc = GoogleBackupService(accessToken: storedToken);
      } else {
        svc = testGoogleBackupServiceFactory!();
      }

      // Create the zip in the system temp dir to avoid polluting app documents
      final file = await (testLocalBackupCreator != null
          ? testLocalBackupCreator!(jsonStr: jsonStr, destinationDirPath: tmpDir.path)
          : BackupService.createLocalBackup(jsonStr: jsonStr, destinationDirPath: tmpDir.path));

      // Notify any test harness that an upload attempt is about to happen.
      try {
        testUploadCompleter?.complete();
      } catch (_) {}
      await svc.uploadBackup(file);
      Log.i('Automatic backup: upload completed successfully to Drive. file=${file.path}', tag: 'BACKUP_AUTO');
      // Optionally delete local file after successful upload
      try {
        if (file.existsSync()) {
          file.deleteSync();
          Log.d('Automatic backup: deleted temp zip ${file.path}', tag: 'BACKUP_AUTO');
        }
        // Remove the temp directory as well
        try {
          if (tmpDir.existsSync()) {
            tmpDir.deleteSync(recursive: true);
            Log.d('Automatic backup: deleted temp dir ${tmpDir.path}', tag: 'BACKUP_AUTO');
          }
        } catch (e) {
          Log.w('Automatic backup: failed deleting temp dir ${tmpDir.path}: $e', tag: 'BACKUP_AUTO');
        }
        // Persist last-success timestamp
        try {
          await PrefsUtils.setLastAutoBackupMs(nowMs);
          _lastSuccess = nowMs;
          Log.i('Automatic backup: recorded last-success ts=$nowMs', tag: 'BACKUP_AUTO');
        } catch (e) {
          Log.w('Automatic backup: failed persisting last-success ts: $e', tag: 'BACKUP_AUTO');
        }
      } catch (e) {
        Log.w('Automatic backup: failed deleting temp files: $e', tag: 'BACKUP_AUTO');
      }
    } catch (e, st) {
      // Don't throw: only log. Apps may query logs to detect failures.
      try {
        Log.e('Automatic backup failed', tag: 'BACKUP_AUTO', error: e, stack: st);
      } catch (_) {}
    }
  }

  // In-memory timestamps to coalesce attempts during a single process run.
  static int? _lastAttempt;
  static int? _lastSuccess;

  // ------------------ Test hooks ------------------
  // Tests may set these to inject fakes and to reset internal state.
  static LocalBackupCreator? testLocalBackupCreator;
  static GoogleBackupServiceFactory? testGoogleBackupServiceFactory;
  // Allows tests to inject a token-loader (used to read stored creds and
  // attempt refresh). If set, it is used instead of creating a default
  // `GoogleBackupService(accessToken: null)` for token checks.
  static GoogleTokenLoaderFactory? testTokenLoaderFactory;

  // Optional test completer that will be completed when an upload is about to
  // happen. Tests can await this to deterministically observe the upload
  // attempt regardless of the actual Google service used.
  static Completer<void>? testUploadCompleter;

  /// Reset internal in-memory state used for coalescing and test hooks.
  static void resetForTests() {
    _lastAttempt = null;
    _lastSuccess = null;
    testLocalBackupCreator = null;
    testGoogleBackupServiceFactory = null;
    testTokenLoaderFactory = null;
    testUploadCompleter = null;
  }
}
