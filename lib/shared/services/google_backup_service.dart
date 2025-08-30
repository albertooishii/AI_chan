import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/services/google_appauth_adapter.dart';
import 'package:ai_chan/shared/services/google_appauth_adapter_mobile.dart';
import 'package:ai_chan/shared/services/google_signin_adapter_mobile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ai_chan/core/config.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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

  /// Nombre fijo del backup en Drive (oculto en appDataFolder)
  static const String backupFileName = 'ai_chan_backup.zip';
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
           uploadEndpoint ?? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
       driveListEndpoint = listEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDownloadEndpoint = downloadEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDeleteEndpoint = deleteEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files');

  /// Placeholder: en una implementación real arrancaría OAuth y guardaría el token.
  Future<void> authenticate() async {
    if (accessToken == null) {
      throw StateError('No access token provided. Implement OAuth2 or pass an accessToken.');
    }
    // noop for now
  }

  // --- Device-flow helpers (Google OAuth 2.0 device code flow) ---
  // Device Authorization Flow removed: using AppAuth (native) + PKCE loopback for web.

  /// Refresh an access token using the stored refresh_token.
  Future<Map<String, dynamic>> refreshAccessToken({required String clientId, String? clientSecret}) async {
    try {
      final creds = await _loadCredentialsSecure();
      if (creds == null) {
        Log.w('GoogleBackupService.refreshAccessToken: no stored credentials', tag: 'GoogleBackup');
        throw StateError('No stored credentials to refresh');
      }

      final refreshToken = creds['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        Log.w(
          'GoogleBackupService.refreshAccessToken: refresh_token missing in stored credentials',
          tag: 'GoogleBackup',
        );
        throw StateError('No refresh_token available; re-authentication required');
      }

      Log.d('GoogleBackupService.refreshAccessToken: attempting token refresh', tag: 'GoogleBackup');

      // Try OAuth2 refresh token grant first (best for Drive API access)
      try {
        final response = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': clientId,
            if (clientSecret != null) 'client_secret': clientSecret,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
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
          Log.d('GoogleBackupService.refreshAccessToken: OAuth refresh successful', tag: 'GoogleBackup');
          return merged;
        } else {
          Log.w(
            'GoogleBackupService.refreshAccessToken: OAuth refresh failed: ${response.statusCode} ${response.body}',
            tag: 'GoogleBackup',
          );
        }
      } catch (e) {
        Log.w('GoogleBackupService.refreshAccessToken: OAuth refresh error: $e', tag: 'GoogleBackup');
      }

      // Fallback: try Firebase token refresh if available
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final idToken = await user.getIdToken(true);
          final tokenMap = <String, dynamic>{
            'access_token': idToken,
            'id_token': idToken,
            'token_type': 'Bearer',
            'expires_in': 3600,
          };

          final merged = <String, dynamic>{};
          merged.addAll(creds);
          merged.addAll(tokenMap);
          if (merged['refresh_token'] == null && refreshToken.isNotEmpty) {
            merged['refresh_token'] = refreshToken;
          }

          await _persistCredentialsSecure(merged);
          Log.d('GoogleBackupService.refreshAccessToken: Firebase fallback successful', tag: 'GoogleBackup');
          return merged;
        }
      } catch (e) {
        Log.w('GoogleBackupService.refreshAccessToken: Firebase fallback failed: $e', tag: 'GoogleBackup');
      }

      throw StateError('Token refresh failed: no valid refresh method available');
    } catch (e) {
      Log.w('GoogleBackupService.refreshAccessToken failed: $e', tag: 'GoogleBackup');
      rethrow;
    }
  }

  // Resolve client id/secret from app config based on the current platform.
  /// Public helper: resolve a client ID using a raw candidate and the app Config.
  /// If `rawCid` is empty or placeholder, checks platform-specific keys in `Config`.
  static Future<String> resolveClientId(String rawCid) async {
    var cid = rawCid.trim();
    if (cid.isEmpty || cid.startsWith('YOUR_') || cid == 'YOUR_GOOGLE_CLIENT_ID') {
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

  /// Attempt to refresh stored credentials using config client id/secret.
  /// Returns the refreshed token map on success.
  Future<Map<String, dynamic>> _attemptRefreshUsingConfig() async {
    try {
      // Resolve client id/secret from config for current platform.
      final clientId = await GoogleBackupService.resolveClientId('');
      final clientSecret = await GoogleBackupService.resolveClientSecret();
      if (clientId.isEmpty) throw StateError('No client id configured for token refresh');
      Log.d(
        'GoogleBackupService._attemptRefreshUsingConfig: attempting refresh with clientId length=${clientId.length}',
        tag: 'GoogleBackup',
      );
      return await refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
    } catch (e) {
      Log.w('GoogleBackupService._attemptRefreshUsingConfig failed: $e', tag: 'GoogleBackup');
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
    List<String> scopes = const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
  }) async {

    // Fallback to AppAuth only for desktop/web (mobile platforms return earlier
    // after using google_sign_in). This prevents AppAuth being invoked a second
    // time on Android/iOS.
    // Delegate to the GoogleAppAuthAdapter for the actual authorize+exchange
    try {
      // Prefer native mobile AppAuth adapter on Android/iOS which uses the
      // flutter_appauth plugin. Desktop continues to use the loopback
      // implementation in GoogleAppAuthAdapter.
      Map<String, dynamic> tokenMap;
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          final mobileAdapter = GoogleAppAuthMobileAdapter(
            scopes: scopes,
            clientId: clientId,
            redirectUri: redirectUri,
          );
          tokenMap = await mobileAdapter.signIn(scopes: scopes);
        } else {
          final adapter = GoogleAppAuthAdapter(scopes: scopes, clientId: clientId, redirectUri: redirectUri);
          tokenMap = await adapter.signIn(scopes: scopes);
        }
      } catch (e) {
        rethrow;
      }
      // persist and return like before
      await _persistCredentialsSecure(tokenMap);
      Log.d('GoogleBackupService: AppAuth credentials persisted securely', tag: 'GoogleBackup');
      return tokenMap;
    } catch (e, st) {
      Log.e('GoogleBackupService: authenticateWithAppAuth failed: $e', tag: 'GoogleBackup', error: e, stack: st);
      rethrow;
    }
  }

  // signInAndExchangeServerAuthCodeLocally removed: local serverAuthCode
  // exchange logic was intentionally deleted per UX/security decisions.

  /// Use native Google Sign-In for Android/iOS with account chooser and refresh token
  Future<Map<String, dynamic>> _signInUsingNativeGoogleSignIn({
    List<String> scopes = const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
    dynamic signInAdapterOverride,
  }) async {
    Log.d('GoogleBackupService._signInUsingNativeGoogleSignIn: using native GoogleSignIn', tag: 'GoogleBackup');

    try {
      if (signInAdapterOverride != null) {
        // Allow tests or callers to inject a custom adapter implementation.
        final adapter = signInAdapterOverride;
        return await adapter.signIn(scopes: scopes);
      }

      // Use native Google Sign-In for Android/iOS - shows native bottom-sheet chooser
      final nativeAdapter = GoogleSignInMobileAdapter(
        scopes: scopes,
        useNativeChooser: true, // Usar chooser nativo (bottom sheet)
      );
      final tokenMap = await nativeAdapter.signIn(scopes: scopes, forceAccountChooser: true);

      // Validate that we obtained the necessary tokens
      final hasAccess = (tokenMap['access_token'] as String?)?.isNotEmpty == true;
      final hasRefresh = (tokenMap['refresh_token'] as String?)?.isNotEmpty == true;
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
      Log.e('GoogleBackupService._signInUsingNativeGoogleSignIn failed: $e', tag: 'GoogleBackup', error: e, stack: st);
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
          Log.d('GoogleBackupService.linkAccount: awaiting existing in-flight link', tag: 'GoogleBackup');
          return _inflightLinkCompleter!.future;
        }
      } catch (_) {
        // If platform checks fail for any reason, conservatively await
        // the existing flow.
        return _inflightLinkCompleter!.future;
      }
    }

    _inflightLinkCompleter = Completer<Map<String, dynamic>>();
    final usedScopes = scopes ?? ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'];
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
        if (stored != null && (stored['access_token'] as String?)?.isNotEmpty == true) {
          final hasRefresh = (stored['refresh_token'] as String?)?.isNotEmpty == true;

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
      if (forceUseGoogleSignIn || kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        final tokenMap = await _signInUsingNativeGoogleSignIn(
          scopes: usedScopes,
          signInAdapterOverride: signInAdapterOverride,
        );
        if (tokenMap['access_token'] != null) {
          await _persistCredentialsSecure(tokenMap);
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
      Log.w('GoogleBackupService.linkAccount: google_sign_in flow failed: $e', tag: 'GoogleBackup');
      Log.d(st.toString(), tag: 'GoogleBackup');
      // If this is web/mobile, do not fallback to AppAuth: surface the error
      // to the caller so the UI can show it. AppAuth is desktop-only.
      try {
        if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) rethrow;
      } catch (_) {
        rethrow;
      }
    }

    // Desktop: use AppAuth. The adapter will manage loopback binding and
    // PKCE exchange itself (avoids relying on flutter_appauth desktop plugin).
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
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
          final tokenMap = await _authenticateWithAppAuth(clientId: desktopCid, redirectUri: null, scopes: usedScopes);
          if (tokenMap['access_token'] != null) {
            await _persistCredentialsSecure(tokenMap);
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
          throw StateError('Fallo al autenticar en escritorio con AppAuth: ${e.toString()}');
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
        await _persistCredentialsSecure(tokenMap);
        _inflightLinkCompleter?.complete(tokenMap);
        _inflightLinkCompleter = null;
        return tokenMap;
      }
    } catch (e) {
      Log.w('GoogleBackupService.linkAccount: AppAuth fallback failed: $e', tag: 'GoogleBackup');
    }

    _inflightLinkCompleter?.completeError(StateError('Linking failed: no tokens obtained'));
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
        if (!kIsWeb && Platform.isAndroid) return 'com.albertooishii.ai_chan:/oauthredirect';
        if (!kIsWeb && Platform.isIOS) return 'com.albertooishii.ai_chan:/oauthredirect';
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
  Future<void> _persistCredentialsSecure(Map<String, dynamic> data) async {
    try {
      // Add a persisted timestamp so callers can decide when to attempt
      // a silent refresh based on token age.
      final merged = <String, dynamic>{};
      merged.addAll(data);
      merged['_persisted_at_ms'] = DateTime.now().millisecondsSinceEpoch;
      await _secureStorage.write(key: 'google_credentials', value: jsonEncode(merged));
      // Log a concise summary so callers can inspect whether a refresh_token
      // was obtained or an access_token is present. Keep this log lightweight.
      try {
        final hasAccess = (merged['access_token'] as String?)?.isNotEmpty == true;
        final hasRefresh = (merged['refresh_token'] as String?)?.isNotEmpty == true;
        final scope = (merged['scope'] as String?) ?? '';
        final persistedAt = merged['_persisted_at_ms'] ?? 0;
        Log.d(
          'GoogleBackupService: persisted credentials. access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope" persisted_at=$persistedAt',
          tag: 'GoogleBackup',
        );
      } catch (_) {}
    } catch (e, st) {
      Log.w('GoogleBackupService: failed to persist credentials: $e', tag: 'GoogleBackup');
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
        final hasRefresh = (map['refresh_token'] as String?)?.isNotEmpty == true;
        final scope = (map['scope'] as String?) ?? '';
        Log.d(
          'GoogleBackupService: loaded stored credentials. access_token? $hasAccess refresh_token? $hasRefresh scopes="$scope"',
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
      Log.d('GoogleBackupService: no stored credentials found', tag: 'GoogleBackup');
    }
    return creds;
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
    var persistedAtMs = (creds?['_persisted_at_ms'] as int?) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = persistedAtMs == 0 ? null : nowMs - persistedAtMs;
    final ageExceeded = ageMs != null && ageMs > _silentRefreshIfOlderThan.inMilliseconds;
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
              hasRefresh = (creds?['refresh_token'] as String?)?.isNotEmpty == true;
            }
          } catch (e) {
            Log.w('GoogleBackupService: non-interactive refresh failed: $e', tag: 'GoogleBackup');
          }
        } else {
          // Try silent sign-in first before giving up
          // This won't show account chooser but may get tokens if user is already signed in
          try {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              final nativeAdapter = GoogleSignInMobileAdapter(
                scopes: ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
                useNativeChooser: true, // Mantener consistente el tipo de chooser
              );
              final silentTokens = await nativeAdapter.signInSilently();
              if (silentTokens != null && silentTokens['access_token'] != null) {
                Log.d('GoogleBackupService: silent sign-in successful, persisting tokens', tag: 'GoogleBackup');
                await _persistCredentialsSecure(silentTokens);
                token = silentTokens['access_token'] as String?;
              } else {
                Log.d('GoogleBackupService: silent sign-in failed, no tokens available', tag: 'GoogleBackup');
              }
            }
          } catch (e) {
            Log.d('GoogleBackupService: silent sign-in attempt failed: $e', tag: 'GoogleBackup');
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
        Log.w('GoogleBackupService: startup token refresh guard encountered error: $e', tag: 'GoogleBackup');
      }
    }
    Log.d('GoogleBackupService: loadStoredAccessToken present? ${token != null}', tag: 'GoogleBackup');
    return token;
  }

  /// Si hay un access_token almacenado, intenta recuperar la información
  /// básica del usuario (userinfo). Devuelve el mapa JSON de userinfo si
  /// la token es válida o tras un refresh exitoso, o `null` si no hay token
  /// o la petición falla.
  Future<Map<String, dynamic>?> fetchUserInfoIfTokenValid() async {
    try {
      final token = await loadStoredAccessToken();
      Log.d('GoogleBackupService: fetchUserInfoIfTokenValid token present? ${token != null}', tag: 'GoogleBackup');
      if (token == null) return null;
      final resp = await httpClient.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $token'},
      );
      Log.d('GoogleBackupService: userinfo HTTP status: ${resp.statusCode}', tag: 'GoogleBackup');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      // If 401 attempt a refresh using stored refresh token and config
      if (resp.statusCode == 401) {
        Log.w('GoogleBackupService: userinfo 401 Unauthorized, attempting refresh', tag: 'GoogleBackup');
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retryClient = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
            final retryResp = await retryClient.httpClient.get(
              Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
              headers: {'Authorization': 'Bearer $newToken'},
            );
            Log.d('GoogleBackupService: retry userinfo HTTP status: ${retryResp.statusCode}', tag: 'GoogleBackup');
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
      // Log a lightweight stack trace so we can identify which caller triggered
      // the credential clear at runtime. Keep the trace short to avoid noisy logs.
      final st = StackTrace.current.toString().split('\n').take(6).join('\n');
      Log.d('GoogleBackupService: cleared stored credentials\n$st', tag: 'GoogleBackup');
    } catch (e, st) {
      Log.w('GoogleBackupService: failed to clear credentials: $e\n${st.toString()}', tag: 'GoogleBackup');
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

    final boundary = 'ai_chan_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/related; boundary=$boundary'};

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

        final updateUrl = Uri.parse('${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=multipart');
        var resUp = await httpClient.patch(updateUrl, headers: headers, body: updateBodyBytes);
        if (resUp.statusCode == 401) {
          try {
            final refreshed = await _attemptRefreshUsingConfig();
            final newToken = refreshed['access_token'] as String?;
            if (newToken != null) {
              final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
              return await retrySvc.uploadBackup(zipFile, filename: filename);
            }
          } catch (_) {}
        }
        if (resUp.statusCode >= 200 && resUp.statusCode < 300) {
          final resp = jsonDecode(resUp.body) as Map<String, dynamic>;
          uploadedFileId = resp['id'] as String;
          Log.d('GoogleBackupService: backup updated successfully, fileId: $uploadedFileId', tag: 'GoogleBackup');

          // Limpiar copias antiguas después de la actualización exitosa
          await _cleanupOldBackups(uploadedFileId);

          return uploadedFileId;
        }
        throw HttpException('Upload (update) failed: ${resUp.statusCode} ${resUp.body}');
      }
    } catch (e) {
      // Si la lista falla por permisos, dejamos que la creación inicial lo intente
      Log.w('GoogleBackupService.uploadBackup: list existing failed: $e', tag: 'GoogleBackup');
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

    var res = await httpClient.post(driveUploadEndpoint, headers: headers, body: createBodyBytes);
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.uploadBackup(zipFile, filename: filename);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final resp = jsonDecode(res.body) as Map<String, dynamic>;
      uploadedFileId = resp['id'] as String;
      Log.d('GoogleBackupService: backup created successfully, fileId: $uploadedFileId', tag: 'GoogleBackup');

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
        resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=resumable');
      } else {
        resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable');
      }
    } catch (_) {
      resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable');
    }
    final initHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': 'application/zip',
    };
    var initRes = await httpClient.post(resumableEndpoint, headers: initHeaders, body: jsonEncode(meta));
    if (!(initRes.statusCode >= 200 && initRes.statusCode < 300)) {
      if (initRes.statusCode == 401) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
            return await retrySvc.uploadBackupResumable(zipFile, filename: filename);
          }
        } catch (_) {}
      }
      throw HttpException('Resumable init failed: ${initRes.statusCode} ${initRes.body}');
    }
    final uploadUrl = initRes.headers['location'] ?? initRes.headers['Location'];
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
    var putRes = await httpClient.put(Uri.parse(uploadUrl), headers: putHeaders, body: bytes);
    if (putRes.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.uploadBackupResumable(zipFile, filename: filename);
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
    throw HttpException('Resumable upload failed: ${putRes.statusCode} ${putRes.body}');
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
      'fields': 'files(id,name,createdTime,size)',
    };
    final q = Uri.parse(driveListEndpoint.toString()).replace(queryParameters: params);
    var res = await httpClient.get(q, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.listBackups(pageSize: pageSize);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final files = (body['files'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      // Ordenar por createdTime desc y devolver
      files.sort((a, b) {
        final ta = a['createdTime'] as String? ?? '';
        final tb = b['createdTime'] as String? ?? '';
        return tb.compareTo(ta);
      });
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
    final url = Uri.parse('${driveDownloadEndpoint.toString()}/$fileId?alt=media');
    var res = await httpClient.get(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
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
    var res = await httpClient.delete(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
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
      Log.d('GoogleBackupService: starting cleanup of old backups, keeping fileId: $keepFileId', tag: 'GoogleBackup');

      final allBackups = await listBackups();
      final oldBackups = allBackups.where((backup) => backup['id'] != keepFileId).toList();

      if (oldBackups.isEmpty) {
        Log.d('GoogleBackupService: no old backups to clean up', tag: 'GoogleBackup');
        return;
      }

      Log.d('GoogleBackupService: found ${oldBackups.length} old backup(s) to delete', tag: 'GoogleBackup');

      // Borrar todas las copias antiguas
      int deletedCount = 0;
      for (final backup in oldBackups) {
        try {
          final fileId = backup['id'] as String;
          final fileName = backup['name'] as String? ?? 'unknown';
          final createdTime = backup['createdTime'] as String? ?? 'unknown';

          await deleteBackup(fileId);
          deletedCount++;
          Log.d(
            'GoogleBackupService: deleted old backup: $fileName (id: $fileId, created: $createdTime)',
            tag: 'GoogleBackup',
          );
        } catch (e) {
          Log.w('GoogleBackupService: failed to delete backup ${backup['id']}: $e', tag: 'GoogleBackup');
          // Continuar borrando otros archivos aunque uno falle
        }
      }

      Log.d('GoogleBackupService: cleanup completed - deleted $deletedCount old backup(s)', tag: 'GoogleBackup');
    } catch (e) {
      Log.w('GoogleBackupService: cleanup failed: $e', tag: 'GoogleBackup');
      // No relanzar el error - el cleanup es opcional y no debe fallar la subida principal
    }
  }
}
