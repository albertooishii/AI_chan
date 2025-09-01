import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/services/google_appauth_adapter.dart';
import 'package:ai_chan/shared/services/google_signin_adapter_mobile.dart';
import 'package:ai_chan/core/config.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Status of Google OAuth consent for Drive API access
enum ConsentStatus {
  notAuthenticated, // User not signed in to any Google account
  authenticatedNoDriveScopes, // User signed in but missing Drive API authorization
  authenticatedWithDriveScopes, // User signed in with full Drive API access
}

/// Servicio esqueleto para subir/descargar backups a Google Drive / GCS.
///
/// NOTA: Esta implementación no realiza OAuth. Está pensada como "punto
/// de partida" y ofrece:
/// - Interfaz clara: authenticate(), uploadBackup(), listBackups(), downloadBackup(), deleteBackup()
/// - Implementación HTTP mínima que asume un token de acceso (Bearer) pasado
///   en cada llamada. En producción deberías implementar OAuth2 (flow de
///   dispositivo o iniciar navegador) o usar credenciales de servicio.
class GoogleBackupService {
  // Single in-flight link completer to avoid concurrent interactive
  // authorization flows (AppAuth / google_sign_in) which can cause
  // multiple loopback servers to bind and lead to timeouts.
  static Completer<Map<String, dynamic>>? _inflightLinkCompleter;

  // 🚨 EMERGENCY STOP: Evitar loop infinito con desvinculación INMEDIATA
  static int _consecutiveRefreshFailures = 0;
  static DateTime? _lastRefreshFailure;
  static const int _maxConsecutiveFailures =
      8; // Increased from 3 to 8 for mobile reliability - connections can be unstable
  static const Duration _circuitBreakerCooldown = Duration(
    minutes: 15, // Increased from 5 to 15 minutes for better user experience
  );

  /// Registrar un fallo de refresh para el circuit breaker
  /// Solo para fallos que realmente indican problemas serios
  static void _recordRefreshFailure([String? reason]) {
    _consecutiveRefreshFailures++;
    _lastRefreshFailure = DateTime.now();

    final status = getCircuitBreakerStatus();
    Log.e(
      '🚨 SERIOUS OAuth failure #$_consecutiveRefreshFailures/$_maxConsecutiveFailures${reason != null ? ' - $reason' : ''}'
      ' | Status: ${status['isActive'] ? 'ACTIVE' : 'MONITORING'}',
      tag: 'GoogleBackup',
    );

    // Log detailed status every few failures
    if (_consecutiveRefreshFailures % 2 == 0) {
      Log.e('Circuit Breaker Status: $status', tag: 'GoogleBackup');
    }
  }

  /// Registrar fallo leve que NO activa circuit breaker
  static void _recordMinorRefreshIssue(String reason) {
    Log.w('OAuth refresh issue (no emergency): $reason', tag: 'GoogleBackup');
  }

  /// Get circuit breaker status for debugging
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

  /// Comprehensive diagnostic method for Android Google Drive session issues
  static Future<Map<String, dynamic>> diagnoseAndroidSessionIssues() async {
    try {
      final diagnosis = <String, dynamic>{
        'platform': Platform.isAndroid ? 'Android' : 'Other',
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

          // Check token expiry if available
          final expiresIn = creds['expires_in'];
          if (expiresIn is int && expiresIn > 0) {
            diagnosis['tokenExpiresInSeconds'] = expiresIn;
          }
        }
      } catch (e) {
        diagnosis['credentialCheckError'] = e.toString();
      }

      // Check native Google Sign-In status
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
        } catch (e) {
          diagnosis['nativeSignInError'] = e.toString();
        }
      }

      Log.i('Android session diagnosis: $diagnosis', tag: 'GoogleBackup');
      return diagnosis;
    } catch (e) {
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
  static void recordOAuthFailure(String reason) {
    _consecutiveRefreshFailures++;
    _lastRefreshFailure = DateTime.now();

    final status = getCircuitBreakerStatus();
    Log.e(
      '🚨 SERIOUS OAuth failure #$_consecutiveRefreshFailures/$_maxConsecutiveFailures${reason.isNotEmpty ? ' - $reason' : ''}'
      ' | Status: ${status['isActive'] ? 'ACTIVE' : 'MONITORING'}',
      tag: 'GoogleBackup',
    );
  }

  /// Helper method for retrying HTTP requests with exponential backoff
  /// Specifically designed for transient network issues on mobile
  static Future<http.Response> _retryHttpRequest(
    Future<http.Response> Function() httpCall,
    String operationName, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await httpCall();

        // Success or non-retryable error
        if (response.statusCode < 500 && response.statusCode != 429) {
          return response;
        }

        // Retryable error (5xx server errors, 429 rate limiting)
        if (attempt < maxRetries) {
          final delay = Duration(
            milliseconds: (initialDelay.inMilliseconds * math.pow(2, attempt))
                .round(),
          );
          Log.d(
            '$operationName: Retryable error ${response.statusCode}, retrying in ${delay.inMilliseconds}ms (attempt ${attempt + 1}/$maxRetries)',
            tag: 'GoogleBackup',
          );
          await Future.delayed(delay);
          continue;
        }

        return response;
      } catch (e) {
        if (attempt < maxRetries) {
          final delay = Duration(
            milliseconds: (initialDelay.inMilliseconds * math.pow(2, attempt))
                .round(),
          );
          Log.d(
            '$operationName: Network error, retrying in ${delay.inMilliseconds}ms (attempt ${attempt + 1}/$maxRetries): $e',
            tag: 'GoogleBackup',
          );
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }

    throw StateError('This should never be reached');
  }

  /// Verificar si necesitamos forzar desvinculación
  static Future<void> _checkForceUnlink() async {
    if (_consecutiveRefreshFailures >= _maxConsecutiveFailures) {
      Log.e('🚨🚨🚨 EMERGENCY UNLINK TRIGGERED! 🚨🚨🚨', tag: 'GoogleBackup');
      await _forceUnlinkGoogleDrive();
    }
  }

  /// Forzar desvinculación completa de Google Drive
  static Future<void> _forceUnlinkGoogleDrive() async {
    try {
      Log.e('🚨 FORCED GOOGLE DRIVE UNLINK STARTING 🚨', tag: 'GoogleBackup');

      // Limpiar credenciales almacenadas
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'google_drive_credentials');
      await storage.delete(key: 'google_credentials');

      // Reset circuit breaker
      _consecutiveRefreshFailures = 0;
      _lastRefreshFailure = null;

      Log.e(
        '🚨 GOOGLE DRIVE UNLINKED - ALL CREDENTIALS DELETED 🚨',
        tag: 'GoogleBackup',
      );
    } catch (e) {
      Log.e('Error al forzar desvinculación: $e', tag: 'GoogleBackup');
    }
  }

  // Constants for consistent backup metadata handling
  static const String backupFileName = 'ai_chan_backup.zip';
  static const String _backupFields =
      'files(id,name,createdTime,modifiedTime,size)';
  static const String _sortByModifiedTime = 'modifiedTime';

  /// Helper to extract backup metadata safely from Drive API response
  static Map<String, String> _extractBackupMetadata(
    Map<String, dynamic> backup,
  ) {
    return {
      'id': backup['id'] as String? ?? 'unknown',
      'name': backup['name'] as String? ?? 'unknown',
      'createdTime': backup['createdTime'] as String? ?? 'unknown',
      'modifiedTime': backup['modifiedTime'] as String? ?? 'unknown',
      'size': backup['size'] as String? ?? 'unknown',
    };
  }

  /// Helper to log backup details consistently
  static void _logBackupDetails(
    List<Map<String, dynamic>> backups,
    String context,
  ) {
    Log.d(
      'GoogleBackupService: found ${backups.length} backup(s) in Drive ($context):',
      tag: 'GoogleBackup',
    );
    for (final backup in backups) {
      final meta = _extractBackupMetadata(backup);
      Log.d(
        '  - ID: ${meta['id']}, Name: ${meta['name']}, Created: ${meta['createdTime']}, Modified: ${meta['modifiedTime']}, Size: ${meta['size']}',
        tag: 'GoogleBackup',
      );
    }
  }

  /// Helper to sort backups by modification time (newest first)
  static void _sortBackupsByModifiedTime(List<Map<String, dynamic>> backups) {
    backups.sort((a, b) {
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
  // If a stored access_token is older than this threshold, attempt a
  // silent sign-in to renew tokens before using the old one.
  static const Duration _silentRefreshIfOlderThan = Duration(minutes: 45);

  /// Construye un servicio con un `accessToken` opcional. Si no hay token,
  /// métodos que requieren autenticación lanzarán StateError.
  GoogleBackupService({
    required this.accessToken,
    http.Client? httpClient,
    Uri? uploadEndpoint,
    Uri? listEndpoint,
    Uri? downloadEndpoint,
    Uri? deleteEndpoint,
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

  /// Placeholder: en una implementación real arrancaría OAuth y guardaría el token.
  Future<void> authenticate() async {
    if (accessToken == null) {
      throw StateError(
        'No access token provided. Implement OAuth2 or pass an accessToken.',
      );
    }
    // noop for now
  }

  // --- Device-flow helpers (Google OAuth 2.0 device code flow) ---
  // Device Authorization Flow removed: using AppAuth (native) + PKCE loopback for web.

  /// Refresh an access token using the stored refresh_token.
  Future<Map<String, dynamic>> refreshAccessToken({
    required String clientId,
    String? clientSecret,
  }) async {
    // 🚨 CIRCUIT BREAKER: Verificar si estamos en cooldown
    if (_consecutiveRefreshFailures >= _maxConsecutiveFailures) {
      if (_lastRefreshFailure != null) {
        final cooldownRemaining =
            _circuitBreakerCooldown -
            DateTime.now().difference(_lastRefreshFailure!);
        if (cooldownRemaining.inSeconds > 0) {
          Log.w(
            'Circuit breaker activo. Cooldown: ${cooldownRemaining.inMinutes}m ${cooldownRemaining.inSeconds % 60}s',
            tag: 'GoogleBackup',
          );
          throw StateError(
            'Circuit breaker: demasiados fallos de refresh consecutivos',
          );
        } else {
          // Reset después del cooldown
          Log.i(
            'Circuit breaker reset después del cooldown',
            tag: 'GoogleBackup',
          );
          _consecutiveRefreshFailures = 0;
          _lastRefreshFailure = null;
        }
      }
    }

    try {
      final creds = await _loadCredentialsSecure();
      if (creds == null) {
        Log.w(
          'GoogleBackupService.refreshAccessToken: no stored credentials',
          tag: 'GoogleBackup',
        );
        _recordMinorRefreshIssue('no stored credentials');
        throw StateError('No stored credentials to refresh');
      }

      final refreshToken = creds['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        Log.w(
          'GoogleBackupService.refreshAccessToken: refresh_token missing in stored credentials',
          tag: 'GoogleBackup',
        );
        _recordMinorRefreshIssue('refresh_token missing');
        throw StateError(
          'No refresh_token available; re-authentication required',
        );
      }

      Log.d(
        'GoogleBackupService.refreshAccessToken: attempting token refresh with retry logic',
        tag: 'GoogleBackup',
      );

      // Try OAuth2 refresh token grant with retry logic for transient failures
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

          // Merge with existing credentials
          final merged = <String, dynamic>{};
          merged.addAll(creds);
          merged.addAll(tokenMap);

          // Preserve refresh_token if not returned in response
          if (merged['refresh_token'] == null && refreshToken.isNotEmpty) {
            merged['refresh_token'] = refreshToken;
          }

          await _persistCredentialsSecure(merged);

          // 🚨 Reset circuit breaker en caso de éxito OAuth
          _consecutiveRefreshFailures = 0;
          _lastRefreshFailure = null;

          Log.d(
            'GoogleBackupService.refreshAccessToken: OAuth refresh successful',
            tag: 'GoogleBackup',
          );
          return merged;
        } else {
          Log.w(
            'GoogleBackupService.refreshAccessToken: OAuth refresh failed: ${response.statusCode} ${response.body}',
            tag: 'GoogleBackup',
          );
          // Only record as serious failure for errors that indicate real auth problems
          if (response.statusCode == 400 &&
              response.body.contains('invalid_grant')) {
            // Token permanently expired - serious problem
            _recordRefreshFailure('invalid_grant - token permanently expired');
            await _checkForceUnlink();
          } else if (response.statusCode == 403 &&
              response.body.contains('access_denied')) {
            // Access revoked by user - serious problem
            _recordRefreshFailure('access_denied - user revoked access');
            await _checkForceUnlink();
          } else if (response.statusCode >= 500) {
            // Server errors are temporary, don't count towards circuit breaker
            _recordMinorRefreshIssue(
              'Server error ${response.statusCode} - temporary issue',
            );
          } else {
            // Other 401/403/429 errors might be temporary (rate limiting, network issues)
            _recordMinorRefreshIssue(
              'HTTP ${response.statusCode} - likely temporary',
            );
          }
        }
      } catch (e) {
        Log.w(
          'GoogleBackupService.refreshAccessToken: OAuth refresh error: $e',
          tag: 'GoogleBackup',
        );
        // Solo registrar como emergencia si es error de red persistente
        _recordMinorRefreshIssue('network error: $e');
      }

      // Si llegamos aquí, OAuth falló pero no necesariamente es emergencia
      _recordMinorRefreshIssue('OAuth failed but not emergency-level');

      throw StateError(
        'OAuth token refresh failed: no valid refresh method available',
      );
    } catch (e) {
      // Solo registrar fallo si es un StateError grave que no fue manejado arriba
      Log.w(
        'GoogleBackupService.refreshAccessToken failed: $e',
        tag: 'GoogleBackup',
      );
      rethrow;
    }
  }

  // Resolve client id/secret from app config based on the current platform.
  /// Public helper: resolve a client ID using a raw candidate and the app Config.
  /// If `rawCid` is empty or placeholder, checks platform-specific keys in `Config`.
  static Future<String> resolveClientId(String rawCid) async {
    var cid = rawCid.trim();
    if (cid.isEmpty ||
        cid.startsWith('YOUR_') ||
        cid == 'YOUR_GOOGLE_CLIENT_ID') {
      try {
        if (kIsWeb) {
          cid = Config.get('GOOGLE_CLIENT_ID_WEB', '');
        } else if (Platform.isAndroid) {
          // Temporal: usar el client_id de escritorio en Android por petición del usuario.
          cid = Config.get('GOOGLE_CLIENT_ID_ANDROID', '');
        } else if (Platform.isIOS) {
          cid = Config.get('GOOGLE_CLIENT_ID_IOS', '');
        } else {
          cid = Config.get('GOOGLE_CLIENT_ID_DESKTOP', '');
        }
      } catch (_) {
        cid = '';
      }
    }
    return cid.trim();
  }

  /// Public helper: resolve a client secret from `Config` for the current platform.
  static Future<String?> resolveClientSecret() async {
    String s = '';
    try {
      // Temporal: usar client secret de escritorio en Android; mantener vacío en iOS.
      if (kIsWeb) {
        s = Config.get('GOOGLE_CLIENT_SECRET_WEB', '');
      } else if (Platform.isAndroid) {
        s = '';
      } else if (Platform.isIOS) {
        s = '';
      } else {
        s = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '');
      }
    } catch (_) {
      s = '';
    }
    s = s.trim();
    return s.isEmpty ? null : s;
  }

  // Backwards-compatible private wrappers used by some UI tests/widgets.
  // These call the public resolution helpers to avoid exposing the full
  // implementation while keeping older call sites working.
  // ...existing code...

  /// Resolve a client id for an explicit target platform string.
  /// Accepted values: 'web', 'android', 'ios', 'desktop'. Returns empty
  /// string on error or if not configured.
  static Future<String> resolveClientIdFor(String target) async {
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
    } catch (_) {
      return '';
    }
  }

  /// Resolve a client secret for an explicit target platform string.
  /// Accepted values: 'web', 'android', 'ios', 'desktop'. Returns null when
  /// no secret is configured or for mobile if empty.
  static Future<String?> resolveClientSecretFor(String target) async {
    try {
      String s = '';
      switch (target) {
        case 'web':
          s = Config.get('GOOGLE_CLIENT_SECRET_WEB', '');
          break;
        case 'android':
          // By default Android may not have a secret; return empty which
          // callers will treat as null. If you previously mapped Android
          // to desktop, use 'desktop' target explicitly.
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
    } catch (_) {
      return null;
    }
  }

  /// Attempt to refresh stored credentials using the original client id/secret
  /// that was used to obtain the tokens, ensuring consistency.
  /// Returns the refreshed token map on success.
  Future<Map<String, dynamic>> _attemptRefreshUsingConfig() async {
    try {
      // First try to use the original client_id that was stored with the credentials
      final storedCreds = await _loadCredentialsSecure();
      String clientId = '';
      String? clientSecret;

      if (storedCreds != null &&
          storedCreds.containsKey('_original_client_id')) {
        // Use the exact same client_id that was used to obtain the original token
        clientId = storedCreds['_original_client_id'] as String? ?? '';
        Log.d(
          'GoogleBackupService._attemptRefreshUsingConfig: using stored original clientId length=${clientId.length}',
          tag: 'GoogleBackup',
        );

        // Determine client secret based on the original client ID pattern
        if (clientId.contains('android')) {
          clientSecret = await GoogleBackupService.resolveClientSecretFor(
            'android',
          );
        } else if (clientId.contains('ios')) {
          clientSecret = await GoogleBackupService.resolveClientSecretFor(
            'ios',
          );
        } else if (clientId.contains('desktop')) {
          clientSecret = await GoogleBackupService.resolveClientSecretFor(
            'desktop',
          );
        } else {
          // Assume web/general client
          clientSecret = await GoogleBackupService.resolveClientSecretFor(
            'web',
          );
        }
      }

      // Fallback: resolve client id/secret from config for current platform if no original stored
      if (clientId.isEmpty) {
        Log.d(
          'GoogleBackupService._attemptRefreshUsingConfig: no original client_id found, falling back to platform-based resolution',
          tag: 'GoogleBackup',
        );
        clientId = await GoogleBackupService.resolveClientId('');
        clientSecret = await GoogleBackupService.resolveClientSecret();
      }

      if (clientId.isEmpty) {
        throw StateError('No client id configured for token refresh');
      }

      Log.d(
        'GoogleBackupService._attemptRefreshUsingConfig: attempting refresh with clientId length=${clientId.length}',
        tag: 'GoogleBackup',
      );
      return await refreshAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
      );
    } catch (e) {
      Log.w(
        'GoogleBackupService._attemptRefreshUsingConfig failed: $e',
        tag: 'GoogleBackup',
      );
      rethrow;
    }
  }

  /// Convenience helper: force the native AppAuth authorization code flow on
  /// the current platform to obtain full tokens (including refresh_token if
  /// the OAuth client and consent prompt allow it).
  ///
  /// Usage: call this on mobile when you specifically need a refresh token
  /// (e.g., to keep server-side access or long-lived Drive backups). It will
  /// pick the platform-specific client id (GOOGLE_CLIENT_ID_ANDROID/IOS) if
  /// available, otherwise falls back to desktop/web client ids.

  /// Exchange an authorization code (from the authorization-code flow) for tokens.
  /// Persists the credentials securely and returns the token map.
  // Authorization code exchange removed: AppAuth (authorizeAndExchangeCode)
  // is the only supported path for exchanging authorization codes.

  // --- AppAuth helper (native PKCE via flutter_appauth) ---
  /// Returns a token map (access_token, refresh_token, expires_in, token_type, scope)
  /// This uses the native AppAuth bindings and PKCE. `redirectUri` is read
  /// from Config if omitted; make sure you configured a platform redirect
  /// URI in your Google Cloud OAuth client (Android/iOS) and `Config`.
  Future<Map<String, dynamic>> _authenticateWithAppAuth({
    required String clientId,
    String? redirectUri,
    List<String> scopes = const [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  }) async {
    // Fallback to AppAuth only for desktop/web (mobile platforms return earlier
    // after using google_sign_in). This prevents AppAuth being invoked a second
    // time on Android/iOS.
    // Delegate to the GoogleAppAuthAdapter for the actual authorize+exchange
    try {
      // Use GoogleAppAuthAdapter for all platforms (desktop loopback implementation)
      // This provides consistent behavior across all platforms
      final adapter = GoogleAppAuthAdapter(
        scopes: scopes,
        clientId: clientId,
        redirectUri: redirectUri,
      );
      final tokenMap = await adapter.signIn(scopes: scopes);

      // persist and return like before, storing the clientId for future refresh operations
      await _persistCredentialsSecure(tokenMap, originalClientId: clientId);
      Log.d(
        'GoogleBackupService: AppAuth credentials persisted securely with original clientId',
        tag: 'GoogleBackup',
      );
      return tokenMap;
    } catch (e, st) {
      Log.e(
        'GoogleBackupService: authenticateWithAppAuth failed: $e',
        tag: 'GoogleBackup',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }

  // signInAndExchangeServerAuthCodeLocally removed: local serverAuthCode
  // exchange logic was intentionally deleted per UX/security decisions.

  /// Use native Google Sign-In for Android/iOS with account chooser and refresh token
  Future<Map<String, dynamic>> _signInUsingNativeGoogleSignIn({
    List<String> scopes = const [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
    dynamic signInAdapterOverride,
  }) async {
    Log.d(
      'GoogleBackupService._signInUsingNativeGoogleSignIn: using native GoogleSignIn',
      tag: 'GoogleBackup',
    );

    try {
      if (signInAdapterOverride != null) {
        // Allow tests or callers to inject a custom adapter implementation.
        final adapter = signInAdapterOverride;
        return await adapter.signIn(scopes: scopes);
      }

      // Use native Google Sign-In for Android/iOS - use native account chooser
      final nativeAdapter = GoogleSignInMobileAdapter(scopes: scopes);
      final tokenMap = await nativeAdapter.signIn(scopes: scopes);

      // Validate that we obtained the necessary tokens
      final hasAccess =
          (tokenMap['access_token'] as String?)?.isNotEmpty == true;
      final hasRefresh =
          (tokenMap['refresh_token'] as String?)?.isNotEmpty == true;
      final scope = (tokenMap['scope'] as String?) ?? '';

      Log.d(
        'GoogleBackupService: native sign-in summary: access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope"',
        tag: 'GoogleBackup',
      );

      // Prefer refresh token from OAuth exchange over Firebase
      if (!hasRefresh) {
        Log.d(
          'GoogleBackupService: native sign-in did not yield refresh_token (normal with native chooser)',
          tag: 'GoogleBackup',
        );
        // Don't throw error - we can still work with access token
      }

      return tokenMap;
    } catch (e, st) {
      Log.e(
        'GoogleBackupService._signInUsingNativeGoogleSignIn failed: $e',
        tag: 'GoogleBackup',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }
  // If callers explicitly request the google_sign_in path on Android,
  // allow starting a fresh interactive flow even if another flow is
  // marked in-flight. This covers the UX case where the native chooser

  /// Public wrapper that performs the full linking/auth flow depending on
  /// the current platform. For web, Android and iOS it uses google_sign_in;
  /// for desktop (Linux/macOS/Windows) it uses AppAuth with an optional
  /// loopback redirect. Returns the token map on success.
  Future<Map<String, dynamic>> linkAccount({
    String? clientId,
    List<String>? scopes,
    dynamic signInAdapterOverride,
    bool forceUseGoogleSignIn = false,
  }) async {
    if (_inflightLinkCompleter != null) {
      // needs to be re-opened after the dialog was closed. For other
      // platforms or when not forcing google_sign_in, await the existing
      // in-flight completer to avoid creating multiple concurrent loopback
      // servers on desktop.
      try {
        if (forceUseGoogleSignIn && !kIsWeb && Platform.isAndroid) {
          Log.d(
            'GoogleBackupService.linkAccount: forceUseGoogleSignIn on Android - starting new flow',
            tag: 'GoogleBackup',
          );
          // fall-through to start a new flow
        } else {
          Log.d(
            'GoogleBackupService.linkAccount: awaiting existing in-flight link',
            tag: 'GoogleBackup',
          );
          return _inflightLinkCompleter!.future;
        }
      } catch (_) {
        // If platform checks fail for any reason, conservatively await
        // the existing flow.
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
    // Resolve a client id if none provided.
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
      } catch (_) {
        cid = '';
      }
    }

    // Short-circuit: if stored credentials already exist, return them instead
    // of starting a new interactive flow. This prevents duplicate AppAuth
    // loopback bindings when the UI or other callers accidentally invoke
    // linkAccount concurrently. Respect explicit forcing of google_sign_in
    // or adapter overrides by skipping this short-circuit in those cases.
    try {
      if (!forceUseGoogleSignIn && signInAdapterOverride == null) {
        final stored = await _loadCredentialsSecure();
        if (stored != null &&
            (stored['access_token'] as String?)?.isNotEmpty == true) {
          final hasRefresh =
              (stored['refresh_token'] as String?)?.isNotEmpty == true;

          // Only attempt server-auth exchange if we have NO refresh token
          // and we're not in a forced sign-in scenario
          if (!hasRefresh) {
            Log.d(
              'GoogleBackupService.linkAccount: stored token has no refresh_token; will trigger new sign-in flow',
              tag: 'GoogleBackup',
            );
            // Don't attempt exchange here - let the main flow handle it
            // This prevents double chooser appearance
          } else {
            Log.d(
              'GoogleBackupService.linkAccount: stored credentials found with refresh_token, returning cached token',
              tag: 'GoogleBackup',
            );
            // Complete the inflight completer so subsequent callers awaiting
            // the in-flight flow do not hang. Then clear it.
            try {
              _inflightLinkCompleter?.complete(stored);
            } catch (_) {}
            _inflightLinkCompleter = null;
            return stored;
          }
        }
      }
    } catch (_) {}

    // Mobile and web: prefer native google_sign_in for better UX
    try {
      if (forceUseGoogleSignIn ||
          kIsWeb ||
          (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        final tokenMap = await _signInUsingNativeGoogleSignIn(
          scopes: usedScopes,
          signInAdapterOverride: signInAdapterOverride,
        );
        if (tokenMap['access_token'] != null) {
          // For mobile platforms, determine the appropriate client ID based on platform
          String? originalClientId;
          try {
            if (!kIsWeb && Platform.isAndroid) {
              originalClientId = await GoogleBackupService.resolveClientIdFor(
                'android',
              );
            } else if (!kIsWeb && Platform.isIOS) {
              originalClientId = await GoogleBackupService.resolveClientIdFor(
                'ios',
              );
            }
          } catch (_) {}

          await _persistCredentialsSecure(
            tokenMap,
            originalClientId: originalClientId,
          );
          // Ensure any awaiters on the inflight completer get the result and
          // the completer is cleared so future flows can start immediately.
          try {
            _inflightLinkCompleter?.complete(tokenMap);
          } catch (_) {}
          _inflightLinkCompleter = null;
          return tokenMap;
        }
      }
    } catch (e, st) {
      Log.w(
        'GoogleBackupService.linkAccount: google_sign_in flow failed: $e',
        tag: 'GoogleBackup',
      );
      Log.d(st.toString(), tag: 'GoogleBackup');
      // If this is web/mobile, do not fallback to AppAuth: surface the error
      // to the caller so the UI can show it. AppAuth is desktop-only.
      try {
        if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
          rethrow;
        }
      } catch (_) {
        rethrow;
      }
    }

    // Desktop: use AppAuth. The adapter will manage loopback binding and
    // PKCE exchange itself (avoids relying on flutter_appauth desktop plugin).
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      // Ensure we have a desktop client id before invoking AppAuth
      var desktopCid = cid;
      if (desktopCid.isEmpty) {
        try {
          desktopCid = await GoogleBackupService.resolveClientIdFor('desktop');
        } catch (_) {
          desktopCid = '';
        }
      }

      if (desktopCid.isEmpty) {
        Log.w(
          'GoogleBackupService.linkAccount: no desktop client id configured (GOOGLE_CLIENT_ID_DESKTOP)',
          tag: 'GoogleBackup',
        );
      } else {
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
            } catch (_) {}
            _inflightLinkCompleter = null;
            return tokenMap;
          }
        } catch (e, st) {
          Log.e(
            'GoogleBackupService.linkAccount: AppAuth desktop flow failed: $e',
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

    // As a final fallback, attempt AppAuth on any platform using resolved desktop client id.
    try {
      final tokenMap = await _authenticateWithAppAuth(
        clientId: cid,
        redirectUri: _defaultRedirectUri(),
        scopes: usedScopes,
      );
      if (tokenMap['access_token'] != null) {
        await _persistCredentialsSecure(tokenMap, originalClientId: cid);
        _inflightLinkCompleter?.complete(tokenMap);
        _inflightLinkCompleter = null;
        return tokenMap;
      }
    } catch (e) {
      Log.w(
        'GoogleBackupService.linkAccount: AppAuth fallback failed: $e',
        tag: 'GoogleBackup',
      );
    }

    _inflightLinkCompleter?.completeError(
      StateError('Linking failed: no tokens obtained'),
    );
    _inflightLinkCompleter = null;
    throw StateError('Linking failed: no tokens obtained');
  }

  static String _defaultRedirectUri() {
    try {
      final cfg = Config.get('GOOGLE_REDIRECT_URI', '').trim();
      if (cfg.isNotEmpty) return cfg;
      // Fallbacks when no explicit redirect uri is configured in .env.
      // Use application-specific custom scheme that matches the
      // `appAuthRedirectScheme` manifest placeholder configured in Gradle.
      // This default should match the redirect intent-filter added by the
      // AppAuth plugin during manifest merging.
      try {
        if (!kIsWeb && Platform.isAndroid) {
          return 'com.albertooishii.ai_chan:/oauthredirect';
        }
        if (!kIsWeb && Platform.isIOS) {
          return 'com.albertooishii.ai_chan:/oauthredirect';
        }
      } catch (_) {}
      Log.d(
        'GoogleBackupService: _defaultRedirectUri resolved to empty (no explicit cfg and not Android/iOS)',
        tag: 'GoogleBackup',
      );
      return '';
    } catch (_) {
      return '';
    }
  }

  // --- Simple credential persistence (for desktop/dev). In production use secure storage. ---
  Future<void> _persistCredentialsSecure(
    Map<String, dynamic> data, {
    String? originalClientId,
  }) async {
    try {
      // Add a persisted timestamp so callers can decide when to attempt
      // a silent refresh based on token age.
      final merged = <String, dynamic>{};
      merged.addAll(data);
      merged['_persisted_at_ms'] = DateTime.now().millisecondsSinceEpoch;

      // Store the original client_id used to obtain these credentials
      // so we can use the same one for refresh operations
      if (originalClientId != null && originalClientId.isNotEmpty) {
        merged['_original_client_id'] = originalClientId;
      } else {
        // Preserve existing original_client_id if we're just updating tokens
        try {
          final existing = await _loadCredentialsSecure();
          if (existing != null && existing.containsKey('_original_client_id')) {
            merged['_original_client_id'] = existing['_original_client_id'];
          }
        } catch (_) {}
      }

      await _secureStorage.write(
        key: 'google_credentials',
        value: jsonEncode(merged),
      );
      // Log a concise summary so callers can inspect whether a refresh_token
      // was obtained or an access_token is present. Keep this log lightweight.
      try {
        final hasAccess =
            (merged['access_token'] as String?)?.isNotEmpty == true;
        final hasRefresh =
            (merged['refresh_token'] as String?)?.isNotEmpty == true;
        final scope = (merged['scope'] as String?) ?? '';
        final persistedAt = merged['_persisted_at_ms'] ?? 0;
        final originalClientId =
            (merged['_original_client_id'] as String?) ?? '';
        Log.d(
          'GoogleBackupService: persisted credentials. access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope" persisted_at=$persistedAt original_client_id_length=${originalClientId.length}',
          tag: 'GoogleBackup',
        );
      } catch (_) {}
    } catch (e, st) {
      Log.w(
        'GoogleBackupService: failed to persist credentials: $e',
        tag: 'GoogleBackup',
      );
      Log.d(st.toString(), tag: 'GoogleBackup');
    }
  }

  Future<Map<String, dynamic>?> _loadCredentialsSecure() async {
    try {
      final v = await _secureStorage.read(key: 'google_credentials');
      if (v == null) return null;
      final map = jsonDecode(v) as Map<String, dynamic>;
      try {
        final hasAccess = (map['access_token'] as String?)?.isNotEmpty == true;
        final hasRefresh =
            (map['refresh_token'] as String?)?.isNotEmpty == true;
        final scope = (map['scope'] as String?) ?? '';
        final originalClientId = (map['_original_client_id'] as String?) ?? '';
        Log.d(
          'GoogleBackupService: loaded stored credentials. access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope" original_client_id_length=${originalClientId.length}',
          tag: 'GoogleBackup',
        );
      } catch (_) {}
      return map;
    } catch (_) {
      return null;
    }
  }

  /// Public helper to load the full stored credentials map (access_token,
  /// refresh_token, scope, etc.). Useful for callers that need to inspect
  /// scopes or refresh tokens before deciding to clear credentials.
  Future<Map<String, dynamic>?> loadStoredCredentials() async {
    final creds = await _loadCredentialsSecure();
    if (creds == null) {
      Log.d(
        'GoogleBackupService: no stored credentials found',
        tag: 'GoogleBackup',
      );
    }
    return creds;
  }

  /// Diagnóstico: verifica el estado de las credenciales almacenadas
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

    Log.d(
      'GoogleBackupService: credential diagnosis: $result',
      tag: 'GoogleBackup',
    );
    return result;
  }

  // --- Server auth-code exchange helpers (obtain refresh_token) ---
  // _exchangeAuthCodeForTokens removed: adapters should call the central
  // exchange helpers in google_oauth_token_exchange.dart when a raw
  // auth code must be exchanged.

  // Produce a redacted summary string for a token map. Shows keys, presence
  // and lengths for string values but never prints token contents.
  // ...existing code...

  /// Devuelve el access_token almacenado si existe, o null.
  Future<String?> loadStoredAccessToken() async {
    // Try to load any stored credentials first
    var creds = await _loadCredentialsSecure();
    var token = creds == null ? null : creds['access_token'] as String?;
    // If there's no stored access token, attempt a silent-only sign-in.
    // Additionally, if we have an access token but no refresh_token, or the
    // token is older than the configured threshold, attempt silent sign-in to
    // refresh tokens silently.
    var hasRefresh = (creds?['refresh_token'] as String?)?.isNotEmpty == true;
    final persistedAtMs = (creds?['_persisted_at_ms'] as int?) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = persistedAtMs == 0 ? null : nowMs - persistedAtMs;
    final ageExceeded =
        ageMs != null && ageMs > _silentRefreshIfOlderThan.inMilliseconds;
    // Avoid starting an interactive sign-in (which opens the native chooser)
    // automatically during app startup. Previously we attempted a
    // server-auth exchange here to obtain a refresh_token when the stored
    // access_token lacked it, but that caused the Google chooser to open
    // unexpectedly. Instead, only try a non-interactive refresh when a
    // stored refresh_token exists; otherwise return the stored access token
    // and let explicit user actions (linkAccount) trigger interactive flows.
    if (token == null || ageExceeded) {
      Log.d(
        'GoogleBackupService: token missing or stale. Will attempt non-interactive refresh only if refresh_token present. tokenPresent=${token != null} refreshPresent=$hasRefresh ageMs=$ageMs',
        tag: 'GoogleBackup',
      );
      try {
        if (hasRefresh) {
          // Try to refresh using stored refresh_token and configured client id/secret.
          try {
            final refreshed = await _attemptRefreshUsingConfig();
            if (refreshed['access_token'] != null) {
              token = refreshed['access_token'] as String?;
              creds = await _loadCredentialsSecure();
              hasRefresh =
                  (creds?['refresh_token'] as String?)?.isNotEmpty == true;
            }
          } catch (e) {
            Log.w(
              'GoogleBackupService: non-interactive refresh failed: $e',
              tag: 'GoogleBackup',
            );
          }
        } else {
          // Try silent sign-in first before giving up
          // This won't show account chooser but may get tokens if user is already signed in
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
                Log.d(
                  'GoogleBackupService: silent sign-in successful, persisting tokens',
                  tag: 'GoogleBackup',
                );
                // For silent sign-in, determine appropriate client ID based on platform
                String? originalClientId;
                try {
                  if (!kIsWeb && Platform.isAndroid) {
                    originalClientId =
                        await GoogleBackupService.resolveClientIdFor('android');
                  } else if (!kIsWeb && Platform.isIOS) {
                    originalClientId =
                        await GoogleBackupService.resolveClientIdFor('ios');
                  }
                } catch (_) {}

                await _persistCredentialsSecure(
                  silentTokens,
                  originalClientId: originalClientId,
                );
                token = silentTokens['access_token'] as String?;
              } else {
                Log.d(
                  'GoogleBackupService: silent sign-in failed, no tokens available',
                  tag: 'GoogleBackup',
                );
              }
            }
          } catch (e) {
            Log.d(
              'GoogleBackupService: silent sign-in attempt failed: $e',
              tag: 'GoogleBackup',
            );
          }

          // If still no token, log that interactive sign-in is required
          if (token == null) {
            Log.d(
              'GoogleBackupService: no refresh_token available and silent sign-in failed; interactive sign-in required',
              tag: 'GoogleBackup',
            );
          }
        }
      } catch (e) {
        Log.w(
          'GoogleBackupService: startup token refresh guard encountered error: $e',
          tag: 'GoogleBackup',
        );
      }
    }
    Log.d(
      'GoogleBackupService: loadStoredAccessToken present? ${token != null}',
      tag: 'GoogleBackup',
    );
    return token;
  }

  /// Loads stored access token WITHOUT any refresh attempts - for diagnostics only.
  /// This method is completely passive and never triggers OAuth flows.
  Future<String?> loadStoredAccessTokenPassive() async {
    try {
      const storage = FlutterSecureStorage();
      final credsStr = await storage.read(key: 'google_credentials');
      if (credsStr != null && credsStr.isNotEmpty) {
        final creds = jsonDecode(credsStr);
        return creds['access_token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Check the current Google OAuth consent status for Drive API access
  /// This helps determine if user is authenticated but missing Drive scopes
  Future<ConsentStatus> checkConsentStatus() async {
    try {
      // First, check if we already have stored credentials with Drive access
      final storedToken = await loadStoredAccessToken();
      if (storedToken != null) {
        // We have stored credentials, assume they include Drive scopes
        return ConsentStatus.authenticatedWithDriveScopes;
      }

      // SIMPLIFIED: Check if we have stored credentials without full token validation
      // This avoids creating additional GoogleSignInMobileAdapter instances that interfere
      try {
        final creds = await _loadCredentialsSecure();
        if (creds == null) {
          // No stored credentials, but we need to check if user is authenticated to Google
          // at the OS level without creating new adapters
          Log.d(
            'GoogleBackupService: no stored credentials found in checkConsentStatus',
            tag: 'GoogleBackup',
          );
          // We can't reliably determine authentication status without interfering
          // with the main flow, so return notAuthenticated and let the main flow handle it
          return ConsentStatus.notAuthenticated;
        }
      } catch (e) {
        Log.w(
          'GoogleBackupService: checkConsentStatus credential check error: $e',
          tag: 'GoogleBackup',
        );
      }

      // Default to not authenticated to avoid interfering with the main flow
      return ConsentStatus.notAuthenticated;
    } catch (e) {
      Log.w(
        'GoogleBackupService: checkConsentStatus error: $e',
        tag: 'GoogleBackup',
      );
      // Default to not authenticated on error
      return ConsentStatus.notAuthenticated;
    }
  }

  /// Si hay un access_token almacenado, intenta recuperar la información
  /// básica del usuario (userinfo). Devuelve el mapa JSON de userinfo si
  /// la token es válida o tras un refresh exitoso, o `null` si no hay token
  /// o la petición falla.
  Future<Map<String, dynamic>?> fetchUserInfoIfTokenValid() async {
    try {
      final token = await loadStoredAccessToken();
      Log.d(
        'GoogleBackupService: fetchUserInfoIfTokenValid token present? ${token != null}',
        tag: 'GoogleBackup',
      );
      if (token == null) return null;
      final resp = await httpClient.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $token'},
      );
      Log.d(
        'GoogleBackupService: userinfo HTTP status: ${resp.statusCode}',
        tag: 'GoogleBackup',
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      // If 401 attempt a refresh using stored refresh token and config
      if (resp.statusCode == 401) {
        Log.w(
          'GoogleBackupService: userinfo 401 Unauthorized, attempting refresh',
          tag: 'GoogleBackup',
        );
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
            Log.d(
              'GoogleBackupService: retry userinfo HTTP status: ${retryResp.statusCode}',
              tag: 'GoogleBackup',
            );
            if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
              return jsonDecode(retryResp.body) as Map<String, dynamic>;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// Borra las credenciales almacenadas en el secure storage (si existen).
  /// Útil para forzar que el usuario vuelva a autenticarse.
  Future<void> clearStoredCredentials() async {
    try {
      await _secureStorage.delete(key: 'google_credentials');
      // También intentar cerrar sesión en GoogleSignIn para limpiar completamente
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
      } catch (e) {
        Log.w(
          'GoogleBackupService: failed to sign out from native adapter: $e',
          tag: 'GoogleBackup',
        );
      }

      // Log a lightweight stack trace so we can identify which caller triggered
      // the credential clear at runtime. Keep the trace short to avoid noisy logs.
      final st = StackTrace.current.toString().split('\n').take(6).join('\n');
      Log.d(
        'GoogleBackupService: cleared stored credentials\n$st',
        tag: 'GoogleBackup',
      );
    } catch (e, st) {
      Log.w(
        'GoogleBackupService: failed to clear credentials: $e\n${st.toString()}',
        tag: 'GoogleBackup',
      );
    }
  }

  Map<String, String> _authHeaders() {
    if (accessToken == null) throw StateError('No access token set');
    return {'Authorization': 'Bearer $accessToken'};
  }

  /// Sube un backup ZIP a Google Drive. Devuelve el fileId si fue exitoso.
  /// Este método construye la petición multipart mínima requerida por Drive.
  Future<String> uploadBackup(File zipFile, {String? filename}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;

    // Metadata completo para creación (incluye parents)
    final createMeta = {
      'name': fn,
      'parents': ['appDataFolder'], // Solo para archivos nuevos
    };

    // Metadata para actualización (SIN parents - causa error 403)
    final updateMeta = {
      'name': fn,
      // NO incluir 'parents' en updates - Drive lo rechaza con 403
    };

    final boundary =
        'ai_chan_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/related; boundary=$boundary',
    };

    // Si ya existe un backup con el mismo nombre en appDataFolder, actualizamos (files.update)
    String uploadedFileId;
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;

        // Crear body para UPDATE (sin parents)
        final List<int> updateBodyBytes = [];
        void addUpdate(String s) => updateBodyBytes.addAll(utf8.encode(s));
        addUpdate('--$boundary\r\n');
        addUpdate('Content-Type: application/json; charset=UTF-8\r\n\r\n');
        addUpdate(jsonEncode(updateMeta)); // Usar metadata sin parents
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
          } catch (_) {}
        }
        if (resUp.statusCode >= 200 && resUp.statusCode < 300) {
          final resp = jsonDecode(resUp.body) as Map<String, dynamic>;
          uploadedFileId = resp['id'] as String;
          Log.d(
            'GoogleBackupService: backup updated successfully, fileId: $uploadedFileId',
            tag: 'GoogleBackup',
          );

          // Limpiar copias antiguas después de la actualización exitosa
          await _cleanupOldBackups(uploadedFileId);

          return uploadedFileId;
        }
        throw HttpException(
          'Upload (update) failed: ${resUp.statusCode} ${resUp.body}',
        );
      }
    } catch (e) {
      // Si la lista falla por permisos, dejamos que la creación inicial lo intente
      Log.w(
        'GoogleBackupService.uploadBackup: list existing failed: $e',
        tag: 'GoogleBackup',
      );
    }

    // Crear archivo nuevo - usar metadata completo con parents
    final List<int> createBodyBytes = [];
    void addCreate(String s) => createBodyBytes.addAll(utf8.encode(s));
    addCreate('--$boundary\r\n');
    addCreate('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    addCreate(jsonEncode(createMeta)); // Usar metadata completo para creación
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
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final resp = jsonDecode(res.body) as Map<String, dynamic>;
      uploadedFileId = resp['id'] as String;
      Log.d(
        'GoogleBackupService: backup created successfully, fileId: $uploadedFileId',
        tag: 'GoogleBackup',
      );

      // Limpiar copias antiguas después de la creación exitosa
      await _cleanupOldBackups(uploadedFileId);

      return uploadedFileId;
    } else {
      throw HttpException('Upload failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Start a resumable upload and upload the file. Returns fileId on success.
  /// This implements a minimal Drive resumable upload: initiate session then PUT bytes.
  Future<String> uploadBackupResumable(File zipFile, {String? filename}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;
    final meta = {
      'name': fn,
      'parents': ['appDataFolder'],
    };

    // Initiate resumable session
    // Si hay un archivo existente, iniciar resumable upload para actualizarlo
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
    } catch (_) {
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
        } catch (_) {}
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

    // Single-shot PUT for now. Could be chunked with Content-Range in a loop.
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
      } catch (_) {}
    }
    if (putRes.statusCode >= 200 && putRes.statusCode < 300) {
      final resp = jsonDecode(putRes.body) as Map<String, dynamic>;
      final uploadedFileId = resp['id'] as String;
      Log.d(
        'GoogleBackupService: resumable backup uploaded successfully, fileId: $uploadedFileId',
        tag: 'GoogleBackup',
      );

      // Limpiar copias antiguas después de la subida exitosa
      await _cleanupOldBackups(uploadedFileId);

      return uploadedFileId;
    }
    throw HttpException(
      'Resumable upload failed: ${putRes.statusCode} ${putRes.body}',
    );
  }

  /// Lista ficheros en Drive que contengan `ai_chan_backup` en el nombre.
  Future<List<Map<String, dynamic>>> listBackups({int pageSize = 50}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    // Buscar en appDataFolder por nombre exacto
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
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final files =
          (body['files'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      // Log backup details for debugging and sort by modification time
      _logBackupDetails(files, 'listBackups');
      _sortBackupsByModifiedTime(files);
      return files;
    } else {
      throw HttpException('List failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Descarga un backup (por fileId) a un archivo local temporal y devuelve el File.
  Future<File> downloadBackup(String fileId, {String? destDir}) async {
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
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await outFile.writeAsBytes(res.bodyBytes, flush: true);
      return outFile;
    } else {
      throw HttpException('Download failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Borra un fichero por fileId en Drive.
  Future<void> deleteBackup(String fileId) async {
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
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw HttpException('Delete failed: ${res.statusCode} ${res.body}');
  }

  /// Limpia copias antiguas de backup, manteniendo solo la más reciente.
  /// [keepFileId] es el ID del archivo que NO se debe borrar (la copia más reciente).
  /// Garantiza que solo exista una copia de seguridad en Google Drive.
  Future<void> _cleanupOldBackups(String keepFileId) async {
    try {
      Log.d(
        'GoogleBackupService: starting cleanup of old backups, keeping fileId: $keepFileId',
        tag: 'GoogleBackup',
      );

      // Get fresh list of all backups
      final allBackups = await listBackups();
      Log.d(
        'GoogleBackupService: found ${allBackups.length} total backup(s) in Drive',
        tag: 'GoogleBackup',
      );

      final oldBackups = allBackups
          .where((backup) => backup['id'] != keepFileId)
          .toList();

      if (oldBackups.isEmpty) {
        Log.d(
          'GoogleBackupService: no old backups to clean up',
          tag: 'GoogleBackup',
        );
        return;
      }

      Log.d(
        'GoogleBackupService: found ${oldBackups.length} old backup(s) to delete',
        tag: 'GoogleBackup',
      );

      // Borrar todas las copias antiguas
      int deletedCount = 0;
      for (final backup in oldBackups) {
        try {
          final meta = _extractBackupMetadata(backup);
          final fileId = meta['id']!;
          final fileName = meta['name']!;

          Log.d(
            'GoogleBackupService: deleting old backup: $fileName (id: $fileId)',
            tag: 'GoogleBackup',
          );
          await deleteBackup(fileId);
          deletedCount++;
          Log.d(
            'GoogleBackupService: successfully deleted old backup: $fileName (id: $fileId, created: ${meta['createdTime']})',
            tag: 'GoogleBackup',
          );
        } catch (e) {
          Log.w(
            'GoogleBackupService: failed to delete backup ${backup['id']}: $e',
            tag: 'GoogleBackup',
          );
          // Continuar borrando otros archivos aunque uno falle
        }
      }

      Log.d(
        'GoogleBackupService: cleanup completed - deleted $deletedCount old backup(s)',
        tag: 'GoogleBackup',
      );

      // Verify cleanup worked by listing backups again
      final remainingBackups = await listBackups();
      Log.d(
        'GoogleBackupService: after cleanup, ${remainingBackups.length} backup(s) remain in Drive',
        tag: 'GoogleBackup',
      );
    } catch (e) {
      Log.w('GoogleBackupService: cleanup failed: $e', tag: 'GoogleBackup');
      // No relanzar el error - el cleanup es opcional y no debe fallar la subida principal
    }
  }

  // ====================================================
  // 🧪 TEST HELPERS - Only for test environment
  // ====================================================

  /// Resets circuit breaker state for testing
  static void resetCircuitBreakerForTest() {
    _consecutiveRefreshFailures = 0;
    _lastRefreshFailure = null;
  }

  /// Forces unlink for testing purposes
  static Future<void> forceUnlinkForTest() async {
    await _forceUnlinkGoogleDrive();
  }
}
