import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/infrastructure/services/google_signin_adapter_mobile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Status of Google OAuth consent for Drive API access
enum ConsentStatus {
  notAuthenticated,
  authenticatedNoDriveScopes,
  authenticatedWithDriveScopes,
}

/// Servicio para manejo de backups en Google Drive con OAuth robusto
class GoogleBackupService {
  GoogleBackupService({
    this.accessToken,
    final http.Client? httpClient,
    final Uri? uploadEndpoint,
    final Uri? listEndpoint,
    final Uri? downloadEndpoint,
    final Uri? deleteEndpoint,
  }) : httpClient = httpClient ?? http.Client(),
       driveUploadEndpoint =
           uploadEndpoint ??
           Uri.parse(
             'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
           ),
       driveListEndpoint =
           listEndpoint ??
           Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDownloadEndpoint =
           downloadEndpoint ??
           Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDeleteEndpoint =
           deleteEndpoint ??
           Uri.parse('https://www.googleapis.com/drive/v3/files');
  // Circuit breaker para evitar loops infinitos de OAuth refresh
  static Completer<Map<String, dynamic>>? _inflightLinkCompleter;
  static int _consecutiveRefreshFailures = 0;
  static DateTime? _lastRefreshFailure;
  static const int _maxConsecutiveFailures = 8;
  static const Duration _circuitBreakerCooldown = Duration(minutes: 15);

  /// Registrar un fallo serio de refresh OAuth
  static void _recordRefreshFailure([final String? reason]) {
    _consecutiveRefreshFailures++;
    _lastRefreshFailure = DateTime.now();
    final status = getCircuitBreakerStatus();
    Log.e(
      'OAuth failure #$_consecutiveRefreshFailures/$_maxConsecutiveFailures${reason != null ? ' - $reason' : ''}'
      ' | Status: ${status['isActive'] ? 'ACTIVE' : 'MONITORING'}',
      tag: 'GoogleBackup',
    );
  }

  /// Registrar fallo leve que NO activa circuit breaker
  static void _recordMinorRefreshIssue(final String reason) {
    Log.w('OAuth refresh issue (no emergency): $reason', tag: 'GoogleBackup');
  }

  /// Get circuit breaker status
  static Map<String, dynamic> getCircuitBreakerStatus() {
    final status = {
      'failures': _consecutiveRefreshFailures,
      'maxFailures': _maxConsecutiveFailures,
      'lastFailure': _lastRefreshFailure?.toIso8601String(),
      'isActive': _consecutiveRefreshFailures >= _maxConsecutiveFailures,
      'cooldownMinutes': _circuitBreakerCooldown.inMinutes,
    };

    if (_lastRefreshFailure != null &&
        _consecutiveRefreshFailures >= _maxConsecutiveFailures) {
      final cooldownRemaining =
          _circuitBreakerCooldown -
          DateTime.now().difference(_lastRefreshFailure!);
      status['cooldownRemainingSeconds'] = math.max(
        0,
        cooldownRemaining.inSeconds,
      );
    }
    return status;
  }

  /// Diagnóstico completo para problemas de OAuth en Android
  static Future<Map<String, dynamic>> diagnoseAndroidSessionIssues() async {
    try {
      String platform = 'Other';
      if (!kIsWeb) {
        if (Platform.isAndroid) {
          platform = 'Android';
        } else if (Platform.isIOS) {
          platform = 'iOS';
        } else if (Platform.isLinux) {
          platform = 'Linux';
        } else if (Platform.isMacOS) {
          platform = 'macOS';
        } else if (Platform.isWindows) {
          platform = 'Windows';
        }
      } else {
        platform = 'Web';
      }

      final diagnosis = <String, dynamic>{
        'platform': platform,
        'circuitBreaker': getCircuitBreakerStatus(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Check stored credentials
      try {
        const storage = FlutterSecureStorage();
        final credsStr = await storage.read(key: 'google_credentials');
        final hasCreds = credsStr != null && credsStr.isNotEmpty;
        diagnosis['hasStoredCredentials'] = hasCreds;

        if (hasCreds) {
          final creds = jsonDecode(credsStr);
          diagnosis['hasRefreshToken'] = creds['refresh_token'] != null;
          diagnosis['hasAccessToken'] = creds['access_token'] != null;
          final expiresIn = creds['expires_in'];
          if (expiresIn is int && expiresIn > 0) {
            diagnosis['tokenExpiresInSeconds'] = expiresIn;
          }
        }
      } on Exception catch (e) {
        diagnosis['credentialCheckError'] = e.toString();
      }

      // Check native Google Sign-In status en Android
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final nativeAdapter = GoogleSignInMobileAdapter(
            scopes: [
              'openid',
              'email',
              'profile',
              'https://www.googleapis.com/auth/drive.appdata',
            ],
          );
          final isSignedIn = await nativeAdapter.isSignedIn();
          diagnosis['nativeSignInStatus'] = isSignedIn;
          if (isSignedIn) {
            final account = await nativeAdapter.getCurrentAccount();
            diagnosis['signedInEmail'] = account?.email ?? 'unknown';
          }
        } on Exception catch (e) {
          diagnosis['nativeSignInError'] = e.toString();
        }
      }

      Log.i('Android session diagnosis: $diagnosis', tag: 'GoogleBackup');
      return diagnosis;
    } on Exception catch (e) {
      Log.e(
        'Failed to diagnose Android session issues: $e',
        tag: 'GoogleBackup',
      );
      return {'error': e.toString()};
    }
  }

  /// Testing helper methods - only for tests
  @visibleForTesting
  static void resetCircuitBreakerForTesting() {
    _consecutiveRefreshFailures = 0;
    _lastRefreshFailure = null;
  }

  @visibleForTesting
  static void recordOAuthFailure(final String reason) {
    _recordRefreshFailure(reason);
  }

  /// Helper method for HTTP requests with exponential backoff
  static Future<http.Response> _retryHttpRequest(
    final Future<http.Response> Function() httpCall,
    final String operationName, {
    final int maxRetries = 3,
    final Duration initialDelay = const Duration(seconds: 1),
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await httpCall();
        if (response.statusCode < 500 && response.statusCode != 429) {
          return response;
        }

        if (attempt < maxRetries) {
          final delay = Duration(
            milliseconds: (initialDelay.inMilliseconds * math.pow(2, attempt))
                .round(),
          );
          Log.d(
            '$operationName: Retrying in ${delay.inMilliseconds}ms (${attempt + 1}/$maxRetries)',
            tag: 'GoogleBackup',
          );
          await Future.delayed(delay);
        }
        return response;
      } on Exception catch (e) {
        if (attempt < maxRetries) {
          final delay = Duration(
            milliseconds: (initialDelay.inMilliseconds * math.pow(2, attempt))
                .round(),
          );
          Log.d(
            '$operationName: Network error, retrying in ${delay.inMilliseconds}ms: $e',
            tag: 'GoogleBackup',
          );
          await Future.delayed(delay);
        } else {
          rethrow;
        }
      }
    }
    throw StateError('This should never be reached');
  }

  /// Verificar si necesitamos forzar desvinculación
  static Future<void> _checkForceUnlink() async {
    if (_consecutiveRefreshFailures >= _maxConsecutiveFailures) {
      Log.e('EMERGENCY UNLINK TRIGGERED!', tag: 'GoogleBackup');
      await _forceUnlinkGoogleDrive();
    }
  }

  /// Forzar desvinculación completa de Google Drive
  static Future<void> _forceUnlinkGoogleDrive() async {
    try {
      Log.e('FORCED GOOGLE DRIVE UNLINK STARTING', tag: 'GoogleBackup');
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'google_drive_credentials');
      await storage.delete(key: 'google_credentials');
      _consecutiveRefreshFailures = 0;
      _lastRefreshFailure = null;
      Log.e(
        'GOOGLE DRIVE UNLINKED - ALL CREDENTIALS DELETED',
        tag: 'GoogleBackup',
      );
    } on Exception catch (e) {
      Log.e('Error al forzar desvinculación: $e', tag: 'GoogleBackup');
    }
  }

  // Constantes para backup
  static const String backupFileName = 'ai_chan_backup.zip';
  static const String _backupFields =
      'files(id,name,createdTime,modifiedTime,size)';
  static const String _sortByModifiedTime = 'modifiedTime';

  /// Extract backup metadata safely
  static Map<String, String> _extractBackupMetadata(
    final Map<String, dynamic> backup,
  ) {
    return {
      'id': backup['id'] as String? ?? 'unknown',
      'name': backup['name'] as String? ?? 'unknown',
      'createdTime': backup['createdTime'] as String? ?? 'unknown',
      'modifiedTime': backup['modifiedTime'] as String? ?? 'unknown',
      'size': backup['size'] as String? ?? 'unknown',
    };
  }

  /// Log backup details
  static void _logBackupDetails(
    final List<Map<String, dynamic>> backups,
    final String context,
  ) {
    Log.d(
      'Found ${backups.length} backup(s) in Drive ($context):',
      tag: 'GoogleBackup',
    );
    for (final backup in backups) {
      final meta = _extractBackupMetadata(backup);
      Log.d(
        '  - ID: ${meta['id']}, Name: ${meta['name']}, Modified: ${meta['modifiedTime']}, Size: ${meta['size']}',
        tag: 'GoogleBackup',
      );
    }
  }

  /// Sort backups by modification time (newest first)
  static void _sortBackupsByModifiedTime(
    final List<Map<String, dynamic>> backups,
  ) {
    backups.sort((final a, final b) {
      final ta = a[_sortByModifiedTime] as String? ?? '';
      final tb = b[_sortByModifiedTime] as String? ?? '';
      return tb.compareTo(ta);
    });
  }

  final String? accessToken;
  final Uri driveUploadEndpoint;
  final Uri driveListEndpoint;
  final Uri driveDownloadEndpoint;
  final Uri driveDeleteEndpoint;
  final http.Client httpClient;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const Duration _silentRefreshIfOlderThan = Duration(hours: 23);

  /// Placeholder para autenticación
  Future<void> authenticate() async {
    if (accessToken == null) {
      throw StateError(
        'No access token provided. Implement OAuth2 or pass an accessToken.',
      );
    }
  }

  /// Refresh access token usando refresh_token almacenado
  Future<Map<String, dynamic>> refreshAccessToken({
    required final String clientId,
    final String? clientSecret,
  }) async {
    // Circuit breaker check
    if (_consecutiveRefreshFailures >= _maxConsecutiveFailures) {
      if (_lastRefreshFailure != null) {
        final cooldownRemaining =
            _circuitBreakerCooldown -
            DateTime.now().difference(_lastRefreshFailure!);
        if (cooldownRemaining.inSeconds > 0) {
          throw StateError(
            'Circuit breaker: demasiados fallos de refresh consecutivos',
          );
        } else {
          _consecutiveRefreshFailures = 0;
          _lastRefreshFailure = null;
        }
      }
    }

    try {
      final creds = await _loadCredentialsSecure();
      if (creds == null) {
        _recordMinorRefreshIssue('no stored credentials');
        throw StateError('No stored credentials to refresh');
      }

      final refreshToken = creds['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        _recordMinorRefreshIssue('refresh_token missing');
        throw StateError(
          'No refresh_token available; re-authentication required',
        );
      }

      Log.d('Attempting OAuth token refresh', tag: 'GoogleBackup');

      try {
        final response = await _retryHttpRequest(
          () => http.post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client_id': clientId,
              if (clientSecret != null) 'client_secret': clientSecret,
              'refresh_token': refreshToken,
              'grant_type': 'refresh_token',
            },
          ),
          'OAuth token refresh',
        );

        if (response.statusCode == 200) {
          final tokenMap = jsonDecode(response.body) as Map<String, dynamic>;
          final merged = <String, dynamic>{}
            ..addAll(creds)
            ..addAll(tokenMap);

          if (merged['refresh_token'] == null && refreshToken.isNotEmpty) {
            merged['refresh_token'] = refreshToken;
          }

          await _persistCredentialsSecure(merged);
          _consecutiveRefreshFailures = 0;
          _lastRefreshFailure = null;

          Log.d('OAuth refresh successful', tag: 'GoogleBackup');
          return merged;
        } else {
          Log.w(
            'OAuth refresh failed: ${response.statusCode} ${response.body}',
            tag: 'GoogleBackup',
          );

          if (response.statusCode == 400 &&
              response.body.contains('invalid_grant')) {
            _recordRefreshFailure('invalid_grant - token permanently expired');
            await _checkForceUnlink();
          } else if (response.statusCode == 403 &&
              response.body.contains('access_denied')) {
            _recordRefreshFailure('access_denied - user revoked access');
            await _checkForceUnlink();
          } else if (response.statusCode >= 500) {
            _recordMinorRefreshIssue(
              'Server error ${response.statusCode} - temporary issue',
            );
          } else {
            _recordMinorRefreshIssue(
              'HTTP ${response.statusCode} - likely temporary',
            );
          }
        }
      } on Exception catch (e) {
        Log.w('OAuth refresh network error: $e', tag: 'GoogleBackup');
        _recordMinorRefreshIssue('network error: $e');
      }

      throw StateError(
        'OAuth token refresh failed: no valid refresh method available',
      );
    } on Exception catch (e) {
      Log.w('refreshAccessToken failed: $e', tag: 'GoogleBackup');
      rethrow;
    }
  }

  /// Resolve client ID for platform
  static Future<String> resolveClientId(final String rawCid) async {
    var cid = rawCid.trim();
    if (cid.isEmpty ||
        cid.startsWith('YOUR_') ||
        cid == 'YOUR_GOOGLE_CLIENT_ID') {
      try {
        if (kIsWeb) {
          cid = Config.get('GOOGLE_CLIENT_ID_WEB', '');
        } else if (Platform.isAndroid) {
          cid = Config.get('GOOGLE_CLIENT_ID_ANDROID', '');
        } else if (Platform.isIOS) {
          cid = Config.get('GOOGLE_CLIENT_ID_IOS', '');
        } else {
          cid = Config.get('GOOGLE_CLIENT_ID_DESKTOP', '');
        }
      } on Exception catch (_) {
        cid = '';
      }
    }
    return cid.trim();
  }

  /// Resolve client secret for platform
  static Future<String?> resolveClientSecret() async {
    String s = '';
    try {
      if (kIsWeb) {
        s = Config.get('GOOGLE_CLIENT_SECRET_WEB', '');
      } else if (Platform.isAndroid) {
        s = '';
      } else if (Platform.isIOS) {
        s = '';
      } else {
        s = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '');
      }
    } on Exception catch (_) {
      s = '';
    }
    s = s.trim();
    return s.isEmpty ? null : s;
  }

  /// Resolve client ID for explicit platform
  static Future<String> resolveClientIdFor(final String target) async {
    try {
      switch (target) {
        case 'web':
          return Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
        case 'android':
          return Config.get('GOOGLE_CLIENT_ID_ANDROID', '').trim();
        case 'ios':
          return Config.get('GOOGLE_CLIENT_ID_IOS', '').trim();
        case 'desktop':
          return Config.get('GOOGLE_CLIENT_ID_DESKTOP', '').trim();
        default:
          return '';
      }
    } on Exception catch (_) {
      return '';
    }
  }

  /// Resolve client secret for explicit platform
  static Future<String?> resolveClientSecretFor(final String target) async {
    try {
      String s = '';
      switch (target) {
        case 'web':
          s = Config.get('GOOGLE_CLIENT_SECRET_WEB', '');
          break;
        case 'android':
          s = Config.get('GOOGLE_CLIENT_SECRET_ANDROID', '');
          break;
        case 'ios':
          s = Config.get('GOOGLE_CLIENT_SECRET_IOS', '');
          break;
        case 'desktop':
          s = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '');
          break;
        default:
          s = '';
      }
      s = s.trim();
      return s.isEmpty ? null : s;
    } on Exception catch (_) {
      return null;
    }
  }

  /// Attempt to refresh using original client credentials for consistency
  Future<Map<String, dynamic>> _attemptRefreshUsingConfig() async {
    try {
      final storedCreds = await _loadCredentialsSecure();
      String clientId = '';
      String? clientSecret;

      if (storedCreds != null &&
          storedCreds.containsKey('_original_client_id')) {
        clientId = storedCreds['_original_client_id'] as String? ?? '';

        String platformKey;
        if (!kIsWeb && Platform.isAndroid) {
          platformKey = 'android';
        } else if (!kIsWeb && Platform.isIOS) {
          platformKey = 'ios';
        } else if (kIsWeb) {
          platformKey = 'web';
        } else {
          platformKey = 'desktop';
        }

        // ANDROID FIX: Use consistent credentials based on stored client ID
        if (clientId.contains('.apps.googleusercontent.com')) {
          final isWebClientId = clientId.contains(
            '-7l7hpj3e5veatm72hc3ehf58u4so6qfo.apps.googleusercontent.com',
          );
          final isDesktopClientId = clientId.contains(
            '-6914hif23kueubs0ptsnshmah8hgdsph.apps.googleusercontent.com',
          );

          if (isWebClientId) {
            clientSecret = await GoogleBackupService.resolveClientSecretFor(
              'web',
            );
          } else if (isDesktopClientId) {
            clientSecret = await GoogleBackupService.resolveClientSecretFor(
              'desktop',
            );
          } else if (!Platform.isAndroid && !Platform.isIOS) {
            clientSecret = await GoogleBackupService.resolveClientSecretFor(
              'web',
            );
          } else {
            clientSecret = null;
          }
        } else {
          clientSecret = await GoogleBackupService.resolveClientSecretFor(
            platformKey,
          );
        }
      }

      if (clientId.isEmpty) {
        clientId = await GoogleBackupService.resolveClientId('');
        clientSecret = await GoogleBackupService.resolveClientSecret();
      }

      if (clientId.isEmpty) {
        throw StateError('No client id configured for token refresh');
      }

      return await refreshAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
      );
    } on Exception catch (e) {
      Log.w('_attemptRefreshUsingConfig failed: $e', tag: 'GoogleBackup');
      rethrow;
    }
  }

  /// AppAuth authentication for desktop platforms
  Future<Map<String, dynamic>> _authenticateWithAppAuth({
    required final String clientId,
    final String? redirectUri,
    final List<String> scopes = const [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  }) async {
    try {
      final adapter = GoogleAppAuthAdapter(
        scopes: scopes,
        clientId: clientId,
        redirectUri: redirectUri,
      );
      final tokenMap = await adapter.signIn(scopes: scopes);
      await _persistCredentialsSecure(tokenMap, originalClientId: clientId);
      return tokenMap;
    } on Exception catch (e, st) {
      Log.e(
        'authenticateWithAppAuth failed: $e',
        tag: 'GoogleBackup',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }

  /// Native Google Sign-In for Android/iOS
  Future<Map<String, dynamic>> _signInUsingNativeGoogleSignIn({
    final List<String> scopes = const [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
    final dynamic signInAdapterOverride,
  }) async {
    try {
      if (signInAdapterOverride != null) {
        final adapter = signInAdapterOverride;
        return await adapter.signIn(scopes: scopes);
      }

      final nativeAdapter = GoogleSignInMobileAdapter(scopes: scopes);
      final tokenMap = await nativeAdapter.signIn(scopes: scopes);

      final hasAccess =
          (tokenMap['access_token'] as String?)?.isNotEmpty == true;
      final hasRefresh =
          (tokenMap['refresh_token'] as String?)?.isNotEmpty == true;
      final scope = (tokenMap['scope'] as String?) ?? '';

      Log.d(
        'Native sign-in: access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope"',
        tag: 'GoogleBackup',
      );

      return tokenMap;
    } on Exception catch (e, st) {
      Log.e(
        '_signInUsingNativeGoogleSignIn failed: $e',
        tag: 'GoogleBackup',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }

  /// Main linking method that handles all platforms
  Future<Map<String, dynamic>> linkAccount({
    final String? clientId,
    final List<String>? scopes,
    final dynamic signInAdapterOverride,
    final bool forceUseGoogleSignIn = false,
  }) async {
    if (_inflightLinkCompleter != null) {
      try {
        if (forceUseGoogleSignIn && !kIsWeb && Platform.isAndroid) {
          Log.d(
            'forceUseGoogleSignIn on Android - starting new flow',
            tag: 'GoogleBackup',
          );
        } else {
          Log.d('Awaiting existing in-flight link', tag: 'GoogleBackup');
          return _inflightLinkCompleter!.future;
        }
      } on Exception catch (_) {
        return _inflightLinkCompleter!.future;
      }
    }

    _inflightLinkCompleter = Completer<Map<String, dynamic>>();
    final usedScopes =
        scopes ??
        [
          'openid',
          'email',
          'profile',
          'https://www.googleapis.com/auth/drive.appdata',
        ];

    String cid = (clientId ?? '').trim();
    if (cid.isEmpty) {
      try {
        if (kIsWeb) {
          cid = await GoogleBackupService.resolveClientIdFor('web');
        } else if (Platform.isAndroid) {
          cid = await GoogleBackupService.resolveClientIdFor('android');
        } else if (Platform.isIOS) {
          cid = await GoogleBackupService.resolveClientIdFor('ios');
        } else {
          cid = await GoogleBackupService.resolveClientIdFor('desktop');
        }
      } on Exception catch (_) {
        cid = '';
      }
    }

    // Check if we already have stored credentials
    try {
      if (!forceUseGoogleSignIn && signInAdapterOverride == null) {
        final stored = await _loadCredentialsSecure();
        if (stored != null &&
            (stored['access_token'] as String?)?.isNotEmpty == true) {
          final hasRefresh =
              (stored['refresh_token'] as String?)?.isNotEmpty == true;
          if (hasRefresh) {
            Log.d(
              'Stored credentials found with refresh_token, returning cached token',
              tag: 'GoogleBackup',
            );
            try {
              _inflightLinkCompleter?.complete(stored);
            } on Exception catch (_) {}
            _inflightLinkCompleter = null;
            return stored;
          }
        }
      }
    } on Exception catch (_) {}

    // Mobile and web: use native google_sign_in
    try {
      if (forceUseGoogleSignIn ||
          kIsWeb ||
          (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        final tokenMap = await _signInUsingNativeGoogleSignIn(
          scopes: usedScopes,
          signInAdapterOverride: signInAdapterOverride,
        );
        if (tokenMap['access_token'] != null) {
          String? originalClientId;
          try {
            originalClientId = await GoogleBackupService.resolveClientIdFor(
              'web',
            );
          } on Exception catch (_) {}

          await _persistCredentialsSecure(
            tokenMap,
            originalClientId: originalClientId,
          );
          try {
            _inflightLinkCompleter?.complete(tokenMap);
          } on Exception catch (_) {}
          _inflightLinkCompleter = null;
          return tokenMap;
        }
      }
    } on Exception catch (e) {
      Log.w('google_sign_in flow failed: $e', tag: 'GoogleBackup');
      try {
        if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
          rethrow;
        }
      } on Exception catch (_) {
        rethrow;
      }
    }

    // Desktop: use AppAuth
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      var desktopCid = cid;
      if (desktopCid.isEmpty) {
        try {
          desktopCid = await GoogleBackupService.resolveClientIdFor('desktop');
        } on Exception catch (_) {
          desktopCid = '';
        }
      }

      if (desktopCid.isNotEmpty) {
        try {
          final tokenMap = await _authenticateWithAppAuth(
            clientId: desktopCid,
            scopes: usedScopes,
          );
          if (tokenMap['access_token'] != null) {
            await _persistCredentialsSecure(
              tokenMap,
              originalClientId: desktopCid,
            );
            try {
              _inflightLinkCompleter?.complete(tokenMap);
            } on Exception catch (_) {}
            _inflightLinkCompleter = null;
            return tokenMap;
          }
        } on Exception catch (e, st) {
          Log.e(
            'AppAuth desktop flow failed: $e',
            tag: 'GoogleBackup',
            error: e,
            stack: st,
          );
          throw StateError(
            'Fallo al autenticar en escritorio con AppAuth: ${e.toString()}',
          );
        }
      }
    }

    _inflightLinkCompleter?.completeError(
      StateError('Linking failed: no tokens obtained'),
    );
    _inflightLinkCompleter = null;
    throw StateError('Linking failed: no tokens obtained');
  }

  /// Persist credentials securely
  Future<void> _persistCredentialsSecure(
    final Map<String, dynamic> data, {
    final String? originalClientId,
  }) async {
    try {
      final merged = <String, dynamic>{}..addAll(data);
      merged['_persisted_at_ms'] = DateTime.now().millisecondsSinceEpoch;

      if (originalClientId != null && originalClientId.isNotEmpty) {
        merged['_original_client_id'] = originalClientId;
      } else {
        try {
          final existing = await _loadCredentialsSecure();
          if (existing != null && existing.containsKey('_original_client_id')) {
            merged['_original_client_id'] = existing['_original_client_id'];
          }
        } on Exception catch (_) {}
      }

      await _secureStorage.write(
        key: 'google_credentials',
        value: jsonEncode(merged),
      );

      final hasAccess = (merged['access_token'] as String?)?.isNotEmpty == true;
      final hasRefresh =
          (merged['refresh_token'] as String?)?.isNotEmpty == true;
      final scope = (merged['scope'] as String?) ?? '';
      Log.d(
        'Persisted credentials: access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope"',
        tag: 'GoogleBackup',
      );
    } on Exception catch (e) {
      Log.w('Failed to persist credentials: $e', tag: 'GoogleBackup');
    }
  }

  Future<Map<String, dynamic>?> _loadCredentialsSecure() async {
    try {
      final v = await _secureStorage.read(key: 'google_credentials');
      if (v == null) return null;
      return jsonDecode(v) as Map<String, dynamic>;
    } on Exception catch (_) {
      return null;
    }
  }

  /// Load stored credentials for inspection
  Future<Map<String, dynamic>?> loadStoredCredentials() async {
    return await _loadCredentialsSecure();
  }

  /// Diagnose stored credentials
  Future<Map<String, dynamic>> diagnoseStoredCredentials() async {
    final creds = await _loadCredentialsSecure();
    final result = <String, dynamic>{
      'has_stored_credentials': creds != null,
      'has_access_token': false,
      'has_refresh_token': false,
      'has_id_token': false,
      'scopes': '',
      'persisted_at': null,
      'age_hours': null,
      'original_client_id': null,
      'original_client_id_length': 0,
    };

    if (creds != null) {
      result['has_access_token'] =
          (creds['access_token'] as String?)?.isNotEmpty == true;
      result['has_refresh_token'] =
          (creds['refresh_token'] as String?)?.isNotEmpty == true;
      result['has_id_token'] =
          (creds['id_token'] as String?)?.isNotEmpty == true;
      result['scopes'] = (creds['scope'] as String?) ?? '';

      final originalClientId = (creds['_original_client_id'] as String?) ?? '';
      result['original_client_id'] = originalClientId.isEmpty
          ? null
          : '${originalClientId.substring(0, 10)}...${originalClientId.substring(originalClientId.length - 10)}';
      result['original_client_id_length'] = originalClientId.length;

      final persistedAtMs = (creds['_persisted_at_ms'] as int?) ?? 0;
      if (persistedAtMs > 0) {
        result['persisted_at'] = DateTime.fromMillisecondsSinceEpoch(
          persistedAtMs,
        );
        final ageMs = DateTime.now().millisecondsSinceEpoch - persistedAtMs;
        result['age_hours'] = ageMs / (1000 * 60 * 60);
      }
    }

    return result;
  }

  /// Load stored access token with optional refresh
  Future<String?> loadStoredAccessToken() async {
    final creds = await _loadCredentialsSecure();
    var token = creds == null ? null : creds['access_token'] as String?;
    final hasRefresh = (creds?['refresh_token'] as String?)?.isNotEmpty == true;
    final persistedAtMs = (creds?['_persisted_at_ms'] as int?) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = persistedAtMs == 0 ? null : nowMs - persistedAtMs;
    final ageExceeded =
        ageMs != null && ageMs > _silentRefreshIfOlderThan.inMilliseconds;

    if (token == null || ageExceeded) {
      try {
        if (hasRefresh) {
          try {
            final refreshed = await _attemptRefreshUsingConfig();
            if (refreshed['access_token'] != null) {
              token = refreshed['access_token'] as String?;
            }
          } on Exception catch (e) {
            Log.w('Non-interactive refresh failed: $e', tag: 'GoogleBackup');
          }
        } else {
          try {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              final nativeAdapter = GoogleSignInMobileAdapter(
                scopes: [
                  'openid',
                  'email',
                  'profile',
                  'https://www.googleapis.com/auth/drive.appdata',
                ],
              );
              final silentTokens = await nativeAdapter.signInSilently();
              if (silentTokens != null &&
                  silentTokens['access_token'] != null) {
                String? originalClientId;
                try {
                  originalClientId =
                      await GoogleBackupService.resolveClientIdFor('web');
                } on Exception catch (_) {}
                await _persistCredentialsSecure(
                  silentTokens,
                  originalClientId: originalClientId,
                );
                token = silentTokens['access_token'] as String?;
              }
            }
          } on Exception catch (e) {
            Log.d('Silent sign-in attempt failed: $e', tag: 'GoogleBackup');
          }
        }
      } on Exception catch (e) {
        Log.w(
          'Startup token refresh guard encountered error: $e',
          tag: 'GoogleBackup',
        );
      }
    }
    return token;
  }

  /// Load stored access token passively (no refresh attempts)
  Future<String?> loadStoredAccessTokenPassive() async {
    try {
      const storage = FlutterSecureStorage();
      final credsStr = await storage.read(key: 'google_credentials');
      if (credsStr != null && credsStr.isNotEmpty) {
        final creds = jsonDecode(credsStr);
        return creds['access_token'] as String?;
      }
    } on Exception catch (_) {}
    return null;
  }

  /// Check OAuth consent status for Drive API
  Future<ConsentStatus> checkConsentStatus() async {
    try {
      final storedToken = await loadStoredAccessToken();
      if (storedToken != null) {
        return ConsentStatus.authenticatedWithDriveScopes;
      }

      try {
        final creds = await _loadCredentialsSecure();
        if (creds == null) {
          return ConsentStatus.notAuthenticated;
        }
      } on Exception catch (e) {
        Log.w(
          'checkConsentStatus credential check error: $e',
          tag: 'GoogleBackup',
        );
      }

      return ConsentStatus.notAuthenticated;
    } on Exception catch (e) {
      Log.w('checkConsentStatus error: $e', tag: 'GoogleBackup');
      return ConsentStatus.notAuthenticated;
    }
  }

  /// Fetch user info using stored token
  Future<Map<String, dynamic>?> fetchUserInfoIfTokenValid() async {
    try {
      final token = await loadStoredAccessToken();
      if (token == null) return null;
      final resp = await httpClient.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      if (resp.statusCode == 401) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retryClient = GoogleBackupService(
              accessToken: newToken,
              httpClient: httpClient,
            );
            final retryResp = await retryClient.httpClient.get(
              Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
              headers: {'Authorization': 'Bearer $newToken'},
            );
            if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
              return jsonDecode(retryResp.body) as Map<String, dynamic>;
            }
          }
        } on Exception catch (_) {}
      }
    } on Exception catch (_) {}
    return null;
  }

  /// Clear stored credentials
  Future<void> clearStoredCredentials() async {
    try {
      await _secureStorage.delete(key: 'google_credentials');
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          final nativeAdapter = GoogleSignInMobileAdapter(
            scopes: [
              'openid',
              'email',
              'profile',
              'https://www.googleapis.com/auth/drive.appdata',
            ],
          );
          await nativeAdapter.signOut();
        }
      } on Exception catch (e) {
        Log.w(
          'Failed to sign out from native adapter: $e',
          tag: 'GoogleBackup',
        );
      }

      Log.d('Cleared stored credentials', tag: 'GoogleBackup');
    } on Exception catch (e) {
      Log.w('Failed to clear credentials: $e', tag: 'GoogleBackup');
    }
  }

  Map<String, String> _authHeaders() {
    if (accessToken == null) throw StateError('No access token set');
    return {'Authorization': 'Bearer $accessToken'};
  }

  /// Robust upload with automatic token refresh (static helper)
  static Future<String> uploadBackupWithAutoRefresh(
    final File zipFile, {
    final String? filename,
    final String? accessToken,
    final bool attemptRefresh = true,
  }) async {
    if (accessToken == null) throw StateError('No access token provided');

    try {
      final svc = GoogleBackupService(accessToken: accessToken);
      final fileId = await svc.uploadBackup(zipFile, filename: filename);
      Log.d(
        'Auto-backup: successful upload, fileId=$fileId',
        tag: 'BACKUP_AUTO',
      );
      return fileId;
    } on Exception catch (e) {
      if (attemptRefresh &&
          (e.toString().contains('401') ||
              e.toString().contains('Unauthorized') ||
              e.toString().contains('invalid_client'))) {
        Log.d(
          'Auto-backup: received OAuth error, attempting automatic token refresh...',
          tag: 'BACKUP_AUTO',
        );

        try {
          final svc = GoogleBackupService();
          final refreshed = await svc.refreshAccessToken(
            clientId: await GoogleBackupService.resolveClientId(''),
            clientSecret: await GoogleBackupService.resolveClientSecret(),
          );

          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            Log.d(
              'Auto-backup: token refresh successful, retrying upload...',
              tag: 'BACKUP_AUTO',
            );
            return await uploadBackupWithAutoRefresh(
              zipFile,
              filename: filename,
              accessToken: newToken,
              attemptRefresh: false,
            );
          }
        } on Exception catch (refreshError) {
          Log.w(
            'Auto-backup: token refresh failed during upload: $refreshError',
            tag: 'BACKUP_AUTO',
          );
        }
      }

      Log.w('Auto-backup: uploadBackup failed: $e', tag: 'BACKUP_AUTO');
      rethrow;
    }
  }

  /// Upload backup to Google Drive
  Future<String> uploadBackup(
    final File zipFile, {
    final String? filename,
  }) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;
    final createMeta = {
      'name': fn,
      'parents': ['appDataFolder'],
    };
    final updateMeta = {'name': fn};

    final boundary =
        'ai_chan_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/related; boundary=$boundary',
    };

    String uploadedFileId;
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;

        final List<int> updateBodyBytes = [];
        void addUpdate(final String s) =>
            updateBodyBytes.addAll(utf8.encode(s));
        addUpdate('--$boundary\r\n');
        addUpdate('Content-Type: application/json; charset=UTF-8\r\n\r\n');
        addUpdate(jsonEncode(updateMeta));
        addUpdate('\r\n');
        addUpdate('--$boundary\r\n');
        addUpdate('Content-Type: application/zip\r\n');
        addUpdate('Content-Transfer-Encoding: binary\r\n\r\n');
        updateBodyBytes.addAll(await zipFile.readAsBytes());
        addUpdate('\r\n--$boundary--\r\n');

        final updateUrl = Uri.parse(
          '${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=multipart',
        );
        final resUp = await httpClient.patch(
          updateUrl,
          headers: headers,
          body: updateBodyBytes,
        );
        if (resUp.statusCode == 401) {
          try {
            final refreshed = await _attemptRefreshUsingConfig();
            final newToken = refreshed['access_token'] as String?;
            if (newToken != null) {
              final retrySvc = GoogleBackupService(
                accessToken: newToken,
                httpClient: httpClient,
              );
              return await retrySvc.uploadBackup(zipFile, filename: filename);
            }
          } on Exception catch (_) {}
        }
        if (resUp.statusCode >= 200 && resUp.statusCode < 300) {
          final resp = jsonDecode(resUp.body) as Map<String, dynamic>;
          uploadedFileId = resp['id'] as String;
          Log.d(
            'Backup updated successfully, fileId: $uploadedFileId',
            tag: 'GoogleBackup',
          );
          await _cleanupOldBackups(uploadedFileId);
          return uploadedFileId;
        }
        throw HttpException(
          'Upload (update) failed: ${resUp.statusCode} ${resUp.body}',
        );
      }
    } on Exception catch (e) {
      Log.w('List existing failed: $e', tag: 'GoogleBackup');
    }

    // Create new file
    final List<int> createBodyBytes = [];
    void addCreate(final String s) => createBodyBytes.addAll(utf8.encode(s));
    addCreate('--$boundary\r\n');
    addCreate('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    addCreate(jsonEncode(createMeta));
    addCreate('\r\n');
    addCreate('--$boundary\r\n');
    addCreate('Content-Type: application/zip\r\n');
    addCreate('Content-Transfer-Encoding: binary\r\n\r\n');
    createBodyBytes.addAll(await zipFile.readAsBytes());
    addCreate('\r\n--$boundary--\r\n');

    final res = await httpClient.post(
      driveUploadEndpoint,
      headers: headers,
      body: createBodyBytes,
    );
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(
            accessToken: newToken,
            httpClient: httpClient,
          );
          return await retrySvc.uploadBackup(zipFile, filename: filename);
        }
      } on Exception catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final resp = jsonDecode(res.body) as Map<String, dynamic>;
      uploadedFileId = resp['id'] as String;
      Log.d(
        'Backup created successfully, fileId: $uploadedFileId',
        tag: 'GoogleBackup',
      );
      await _cleanupOldBackups(uploadedFileId);
      return uploadedFileId;
    } else {
      throw HttpException('Upload failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Upload with resumable protocol
  Future<String> uploadBackupResumable(
    final File zipFile, {
    final String? filename,
  }) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;
    final meta = {
      'name': fn,
      'parents': ['appDataFolder'],
    };

    Uri resumableEndpoint;
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;
        resumableEndpoint = Uri.parse(
          '${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=resumable',
        );
      } else {
        resumableEndpoint = Uri.parse(
          '${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable',
        );
      }
    } on Exception catch (_) {
      resumableEndpoint = Uri.parse(
        '${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable',
      );
    }

    final initHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': 'application/zip',
    };
    final initRes = await httpClient.post(
      resumableEndpoint,
      headers: initHeaders,
      body: jsonEncode(meta),
    );
    if (!(initRes.statusCode >= 200 && initRes.statusCode < 300)) {
      if (initRes.statusCode == 401) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retrySvc = GoogleBackupService(
              accessToken: newToken,
              httpClient: httpClient,
            );
            return await retrySvc.uploadBackupResumable(
              zipFile,
              filename: filename,
            );
          }
        } on Exception catch (_) {}
      }
      throw HttpException(
        'Resumable init failed: ${initRes.statusCode} ${initRes.body}',
      );
    }

    final uploadUrl =
        initRes.headers['location'] ?? initRes.headers['Location'];
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw StateError('Resumable upload URL not provided by server');
    }

    final bytes = await zipFile.readAsBytes();
    final putHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/zip',
      'Content-Length': bytes.length.toString(),
      'Content-Range': 'bytes 0-${bytes.length - 1}/${bytes.length}',
    };
    final putRes = await httpClient.put(
      Uri.parse(uploadUrl),
      headers: putHeaders,
      body: bytes,
    );
    if (putRes.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(
            accessToken: newToken,
            httpClient: httpClient,
          );
          return await retrySvc.uploadBackupResumable(
            zipFile,
            filename: filename,
          );
        }
      } on Exception catch (_) {}
    }
    if (putRes.statusCode >= 200 && putRes.statusCode < 300) {
      final resp = jsonDecode(putRes.body) as Map<String, dynamic>;
      final uploadedFileId = resp['id'] as String;
      Log.d(
        'Resumable backup uploaded successfully, fileId: $uploadedFileId',
        tag: 'GoogleBackup',
      );
      await _cleanupOldBackups(uploadedFileId);
      return uploadedFileId;
    }
    throw HttpException(
      'Resumable upload failed: ${putRes.statusCode} ${putRes.body}',
    );
  }

  /// List backups in Google Drive
  Future<List<Map<String, dynamic>>> listBackups({
    final int pageSize = 50,
  }) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final params = {
      'q': 'name = "$backupFileName"',
      'spaces': 'appDataFolder',
      'pageSize': pageSize.toString(),
      'fields': _backupFields,
    };
    final q = Uri.parse(
      driveListEndpoint.toString(),
    ).replace(queryParameters: params);
    final res = await httpClient.get(q, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(
            accessToken: newToken,
            httpClient: httpClient,
          );
          return await retrySvc.listBackups(pageSize: pageSize);
        }
      } on Exception catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final files =
          (body['files'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      _logBackupDetails(files, 'listBackups');
      _sortBackupsByModifiedTime(files);
      return files;
    } else {
      throw HttpException('List failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Download backup from Google Drive
  Future<File> downloadBackup(
    final String fileId, {
    final String? destDir,
  }) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    final d = destDir ?? Directory.systemTemp.path;
    final outFile = File('$d/ai_chan_backup_$fileId.zip');
    final url = Uri.parse(
      '${driveDownloadEndpoint.toString()}/$fileId?alt=media',
    );
    final res = await httpClient.get(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(
            accessToken: newToken,
            httpClient: httpClient,
          );
          return await retrySvc.downloadBackup(fileId, destDir: destDir);
        }
      } on Exception catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await outFile.writeAsBytes(res.bodyBytes, flush: true);
      return outFile;
    } else {
      throw HttpException('Download failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Delete backup from Google Drive
  Future<void> deleteBackup(final String fileId) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    final url = Uri.parse('${driveDeleteEndpoint.toString()}/$fileId');
    final res = await httpClient.delete(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(
            accessToken: newToken,
            httpClient: httpClient,
          );
          return await retrySvc.deleteBackup(fileId);
        }
      } on Exception catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw HttpException('Delete failed: ${res.statusCode} ${res.body}');
  }

  /// Clean up old backups, keeping only the most recent
  Future<void> _cleanupOldBackups(final String keepFileId) async {
    try {
      Log.d(
        'Starting cleanup of old backups, keeping fileId: $keepFileId',
        tag: 'GoogleBackup',
      );

      final allBackups = await listBackups();
      final oldBackups = allBackups
          .where((final backup) => backup['id'] != keepFileId)
          .toList();

      if (oldBackups.isEmpty) {
        Log.d('No old backups to clean up', tag: 'GoogleBackup');
        return;
      }

      int deletedCount = 0;
      for (final backup in oldBackups) {
        try {
          final meta = _extractBackupMetadata(backup);
          final fileId = meta['id']!;
          await deleteBackup(fileId);
          deletedCount++;
        } on Exception catch (e) {
          Log.w(
            'Failed to delete backup ${backup['id']}: $e',
            tag: 'GoogleBackup',
          );
        }
      }

      Log.d(
        'Cleanup completed - deleted $deletedCount old backup(s)',
        tag: 'GoogleBackup',
      );
    } on Exception catch (e) {
      Log.w('Cleanup failed: $e', tag: 'GoogleBackup');
    }
  }

  // Test helpers
  static void resetCircuitBreakerForTest() {
    _consecutiveRefreshFailures = 0;
    _lastRefreshFailure = null;
  }

  static Future<void> forceUnlinkForTest() async {
    await _forceUnlinkGoogleDrive();
  }

  /// Force token age and refresh with diagnostics (debug method)
  Future<Map<String, dynamic>> forceTokenAgeAndRefreshWithDiagnostics() async {
    final steps = <String>[];

    try {
      steps.add('Starting token age and refresh diagnostics...');

      final stored = await _loadCredentialsSecure();
      if (stored == null) {
        steps.add('No stored credentials found');
        return {'steps': steps, 'result': 'No credentials'};
      }

      steps.add('Found stored credentials');

      final hasRefresh =
          (stored['refresh_token'] as String?)?.isNotEmpty == true;
      steps.add('Has refresh token: $hasRefresh');

      if (hasRefresh) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          steps.add('Token refresh successful');
          return {'steps': steps, 'result': 'Success', 'tokens': refreshed};
        } on Exception catch (e) {
          steps.add('Token refresh failed: $e');
          return {
            'steps': steps,
            'result': 'Refresh failed',
            'error': e.toString(),
          };
        }
      } else {
        steps.add('No refresh token available');
        return {'steps': steps, 'result': 'No refresh token'};
      }
    } on Exception catch (e) {
      steps.add('Diagnostics error: $e');
      return {'steps': steps, 'result': 'Error', 'error': e.toString()};
    }
  }

  /// Obtiene información del usuario desde Google OAuth API
  Future<Map<String, dynamic>?> getUserInfo() async {
    if (accessToken == null) return null;

    try {
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return {
          'email': data['email'] as String?,
          'avatarUrl': data['picture'] as String?,
          'name': data['name'] as String?,
        };
      }

      Log.w(
        'Error getting user info: ${resp.statusCode} - ${resp.body}',
        tag: 'GoogleBackup',
      );
      return null;
    } on Exception catch (e) {
      Log.e('Exception getting user info: $e', tag: 'GoogleBackup');
      return null;
    }
  }

  /// Crea un backup temporal preparado para subida
  Future<File> createTemporaryBackupFile(final String jsonData) async {
    final tempDir = await getTemporaryDirectory();
    return await BackupService.createLocalBackup(
      jsonStr: jsonData,
      destinationDirPath: tempDir.path,
    );
  }
}
