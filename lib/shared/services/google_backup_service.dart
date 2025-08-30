import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/services/google_appauth_adapter.dart';
import 'package:ai_chan/core/config.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ai_chan/shared/services/google_sign_in_adapter.dart';

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
    // Implement OAuth2 refresh_token grant against Google's token endpoint.
    // Notes:
    // - clientSecret may be required for certain OAuth clients. Storing a
    //   client secret on-device is insecure; prefer refreshing on a trusted
    //   backend when possible.
    // - If no refresh_token is stored, the caller should re-authenticate.
    try {
      final creds = await _loadCredentialsSecure();
      if (creds == null) throw StateError('No stored credentials to refresh');
      final refreshToken = creds['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw StateError('No refresh_token available; re-authentication required');
      }

      final tokenEndpoint = Uri.parse('https://oauth2.googleapis.com/token');
      final body = {'grant_type': 'refresh_token', 'refresh_token': refreshToken, 'client_id': clientId};
      if (clientSecret != null && clientSecret.isNotEmpty) body['client_secret'] = clientSecret;

      final res = await httpClient.post(
        tokenEndpoint,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Refresh failed: ${res.statusCode} ${res.body}');
      }
      final tokenMap = jsonDecode(res.body) as Map<String, dynamic>;

      // Merge returned fields with existing stored credentials. Some responses
      // may not include the refresh_token; preserve the stored one in that case.
      final merged = <String, dynamic>{};
      merged.addAll(creds);
      merged.addAll(tokenMap);
      if (merged['refresh_token'] == null && refreshToken.isNotEmpty) merged['refresh_token'] = refreshToken;

      // Persist merged credentials so future calls can reuse the refresh token.
      await _persistCredentialsSecure(merged);

      return merged;
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
  Future<Map<String, dynamic>> authenticateWithNativeAppAuth({String? clientId, String? redirectUri}) async {
    var cid = (clientId ?? '').trim();
    if (cid.isEmpty) {
      try {
        if (!kIsWeb && Platform.isAndroid) {
          cid = await GoogleBackupService.resolveClientIdFor('android');
        } else if (!kIsWeb && Platform.isIOS) {
          cid = await GoogleBackupService.resolveClientIdFor('ios');
        } else {
          cid = await GoogleBackupService.resolveClientIdFor('desktop');
        }
      } catch (_) {
        cid = '';
      }
    }
    if (cid.isEmpty) {
      // Last resort: generic resolution (reads env keys based on platform)
      cid = await GoogleBackupService.resolveClientId('');
    }
    if (cid.isEmpty) {
      throw StateError(
        'No OAuth client ID configured for AppAuth on this platform. Please set the appropriate GOOGLE_CLIENT_ID_* in .env',
      );
    }
    Log.d(
      'GoogleBackupService: authenticateWithNativeAppAuth resolved clientId length=${cid.length}',
      tag: 'GoogleBackup',
    );
    // Do NOT force AppAuth on mobile — prefer the google_sign_in experience
    // which uses native Play Services / iOS sign-in and avoids showing the
    // AppAuth web-popup. If callers truly need AppAuth on mobile they should
    // call authenticateWithAppAuth(...) explicitly with forceAppAuth=true.
    return await authenticateWithAppAuth(clientId: cid, redirectUri: redirectUri, forceAppAuth: false);
  }

  /// Exchange an authorization code (from the authorization-code flow) for tokens.
  /// Persists the credentials securely and returns the token map.
  // Authorization code exchange removed: AppAuth (authorizeAndExchangeCode)
  // is the only supported path for exchanging authorization codes.

  // --- AppAuth helper (native PKCE via flutter_appauth) ---
  /// Returns a token map (access_token, refresh_token, expires_in, token_type, scope)
  /// This uses the native AppAuth bindings and PKCE. `redirectUri` is read
  /// from Config if omitted; make sure you configured a platform redirect
  /// URI in your Google Cloud OAuth client (Android/iOS) and `Config`.
  Future<Map<String, dynamic>> authenticateWithAppAuth({
    required String clientId,
    String? redirectUri,
    List<String> scopes = const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
    bool forceAppAuth = false,
  }) async {
    // Removed google_sign_in usage: use AppAuth (PKCE) for all non-web platforms.

    // Fallback to AppAuth only for desktop/web (mobile platforms return earlier
    // after using google_sign_in). This prevents AppAuth being invoked a second
    // time on Android/iOS.
    // Delegate to the GoogleAppAuthAdapter for the actual authorize+exchange
    try {
      final adapter = GoogleAppAuthAdapter(scopes: scopes, clientId: clientId, redirectUri: redirectUri);
      final tokenMap = await adapter.signIn(scopes: scopes);
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

  /// Use the google_sign_in plugin to sign in on web/mobile and return a token map.
  Future<Map<String, dynamic>> _signInUsingGoogleSignIn({
    List<String> scopes = const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
    dynamic signInAdapterOverride,
  }) async {
    Log.d('GoogleBackupService._signInUsingGoogleSignIn: using GoogleSignInAdapter', tag: 'GoogleBackup');
    // Use the platform adapter which will throw on desktop. Do not fallback
    // to AppAuth here — callers expect google_sign_in on mobile/web.
    String? platformClientId;
    String? platformServerClientId;
    try {
      if (kIsWeb) {
        platformClientId = await GoogleBackupService.resolveClientIdFor('web');
        platformServerClientId = null;
      } else if (Platform.isAndroid) {
        platformClientId = await GoogleBackupService.resolveClientIdFor('android');
        // Android expects a serverClientId (the web client id) for certain auth flows
        platformServerClientId = await GoogleBackupService.resolveClientIdFor('web');
      } else if (Platform.isIOS) {
        platformClientId = await GoogleBackupService.resolveClientIdFor('ios');
        platformServerClientId = null;
      } else {
        platformClientId = null;
        platformServerClientId = null;
      }
    } catch (_) {
      platformClientId = null;
      platformServerClientId = null;
    }
    final adapter =
        signInAdapterOverride ??
        GoogleSignInAdapter(scopes: scopes, clientId: platformClientId, serverClientId: platformServerClientId);
    try {
      final tokenMap = await adapter.signIn(scopes: scopes);
      return tokenMap;
    } on NoSuchMethodError catch (e) {
      Log.d('GoogleBackupService._signInUsingGoogleSignIn: NoSuchMethodError from adapter: $e', tag: 'GoogleBackup');
      throw StateError('El método de inicio de sesión nativo no está disponible en este dispositivo');
    }
  }

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
    Log.d('GoogleBackupService.linkAccount: invoked (clientId length=${clientId?.length ?? 0})', tag: 'GoogleBackup');
    // If a link is already in progress, await its result instead of starting
    // a new interactive flow. This prevents multiple loopback servers from
    // being created on desktop and reduces race conditions when callers
    // re-open the dialog rapidly.
    if (_inflightLinkCompleter != null) {
      // If callers explicitly request the google_sign_in path on Android,
      // allow starting a fresh interactive flow even if another flow is
      // marked in-flight. This covers the UX case where the native chooser
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
          Log.d(
            'GoogleBackupService.linkAccount: stored credentials found, returning cached token',
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
    } catch (_) {}

    // Mobile and web: prefer google_sign_in
    try {
      if (forceUseGoogleSignIn || kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        final tokenMap = await _signInUsingGoogleSignIn(
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
          final tokenMap = await authenticateWithAppAuth(clientId: desktopCid, redirectUri: null, scopes: usedScopes);
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
      final tokenMap = await authenticateWithAppAuth(
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

  /// Refresh tokens using AppAuth if possible. Falls back to HTTP token endpoint
  /// when AppAuth is not available or returns null.
  Future<Map<String, dynamic>> refreshAccessTokenWithAppAuth({
    required String clientId,
    String? refreshToken,
    String? redirectUri,
  }) async {
    // Refresh via AppAuth removed — use re-authentication.
    throw StateError('Token refresh with AppAuth is not supported.');
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
      await _secureStorage.write(key: 'google_credentials', value: jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCredentialsSecure() async {
    try {
      final v = await _secureStorage.read(key: 'google_credentials');
      if (v == null) return null;
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Public helper to load the full stored credentials map (access_token,
  /// refresh_token, scope, etc.). Useful for callers that need to inspect
  /// scopes or refresh tokens before deciding to clear credentials.
  Future<Map<String, dynamic>?> loadStoredCredentials() async {
    return await _loadCredentialsSecure();
  }

  /// Devuelve el access_token almacenado si existe, o null.
  Future<String?> loadStoredAccessToken() async {
    final creds = await _loadCredentialsSecure();
    return creds == null ? null : creds['access_token'] as String?;
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

    final meta = {
      'name': fn,
      // Guardar en appDataFolder para mantenerlo oculto
      'parents': ['appDataFolder'],
    };

    final boundary = 'ai_chan_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/related; boundary=$boundary'};

    final List<int> bodyBytes = [];
    void add(String s) => bodyBytes.addAll(utf8.encode(s));

    add('--$boundary\r\n');
    add('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    add(jsonEncode(meta));
    add('\r\n');
    add('--$boundary\r\n');
    add('Content-Type: application/zip\r\n');
    add('Content-Transfer-Encoding: binary\r\n\r\n');
    bodyBytes.addAll(await zipFile.readAsBytes());
    add('\r\n--$boundary--\r\n');

    // Si ya existe un backup con el mismo nombre en appDataFolder, actualizamos (files.update)
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;
        final updateUrl = Uri.parse('${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=multipart');
        var resUp = await httpClient.patch(updateUrl, headers: headers, body: bodyBytes);
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
          return resp['id'] as String;
        }
        throw HttpException('Upload (update) failed: ${resUp.statusCode} ${resUp.body}');
      }
    } catch (e) {
      // Si la lista falla por permisos, dejamos que la creación inicial lo intente
      Log.w('GoogleBackupService.uploadBackup: list existing failed: $e', tag: 'GoogleBackup');
    }

    var res = await httpClient.post(driveUploadEndpoint, headers: headers, body: bodyBytes);
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
      return resp['id'] as String;
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
      return resp['id'] as String;
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
}
