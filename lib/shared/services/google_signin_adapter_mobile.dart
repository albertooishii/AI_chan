import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:http/http.dart' as http;

/// Native Google Sign-In adapter for Android/iOS with proper token handling
/// Updated for google_sign_in ^7.1.1 API
class GoogleSignInMobileAdapter {
  final List<String> scopes;
  final String? clientId;
  final String? serverClientId;

  bool _isInitialized = false;
  GoogleSignInAccount? _currentUser;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  late final GoogleSignIn _signIn;

  GoogleSignInMobileAdapter({required this.scopes, this.clientId, this.serverClientId}) {
    // Create GoogleSignIn instance configured with our scopes for proper consent flow
    _signIn = GoogleSignIn.instance;
  }

  /// Initialize the adapter and configure GoogleSignIn
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final resolvedClientId = clientId ?? _resolveClientId();
      final resolvedServerClientId = serverClientId ?? _resolveServerClientId();

      await _signIn.initialize(clientId: resolvedClientId, serverClientId: resolvedServerClientId);

      // Subscribe to authentication events
      _authSubscription = _signIn.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: _handleAuthenticationError,
      );

      _isInitialized = true;

      Log.d('GoogleSignInMobileAdapter: initialized successfully', tag: 'GoogleSignIn');
    } catch (e, st) {
      Log.e('GoogleSignInMobileAdapter: initialization failed: $e', tag: 'GoogleSignIn', error: e, stack: st);
      throw StateError('Google Sign-In initialization failed: $e');
    }
  }

  /// Handle authentication events from GoogleSignIn
  Future<void> _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _currentUser = event.user;
        Log.d('GoogleSignInMobileAdapter: user signed in: ${event.user.email}', tag: 'GoogleSignIn');
        break;
      case GoogleSignInAuthenticationEventSignOut():
        _currentUser = null;
        Log.d('GoogleSignInMobileAdapter: user signed out', tag: 'GoogleSignIn');
        break;
    }
  }

  /// Handle authentication errors
  Future<void> _handleAuthenticationError(Object error) async {
    Log.e('GoogleSignInMobileAdapter: authentication error: $error', tag: 'GoogleSignIn', error: error);
  }

  /// Resolve client ID from configuration
  String? _resolveClientId() {
    if (clientId != null && clientId!.isNotEmpty) return clientId;

    try {
      // For mobile platforms, use platform-specific client IDs
      if (Platform.isAndroid) {
        final androidClientId = Config.get('GOOGLE_CLIENT_ID_ANDROID', '').trim();
        if (androidClientId.isNotEmpty) return androidClientId;
      } else if (Platform.isIOS) {
        final iosClientId = Config.get('GOOGLE_CLIENT_ID_IOS', '').trim();
        if (iosClientId.isNotEmpty) return iosClientId;
      }

      // Fallback to web client ID
      final webClientId = Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
      if (webClientId.isNotEmpty) {
        Log.d('GoogleSignInMobileAdapter: using web clientId as fallback', tag: 'GoogleSignIn');
        return webClientId;
      }
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: error resolving clientId: $e', tag: 'GoogleSignIn');
    }

    return null;
  }

  /// Resolve server client ID for server auth code
  String? _resolveServerClientId() {
    if (serverClientId != null && serverClientId!.isNotEmpty) return serverClientId;

    try {
      // Server client ID is always the web client ID
      final webClientId = Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
      if (webClientId.isNotEmpty) {
        Log.d('GoogleSignInMobileAdapter: using web clientId for server auth code', tag: 'GoogleSignIn');
        return webClientId;
      }
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: error resolving server clientId: $e', tag: 'GoogleSignIn');
    }

    return null;
  }

  /// Sign in with Google and obtain tokens including refresh_token
  Future<Map<String, dynamic>> signIn({List<String>? scopes, bool forceAccountChooser = true}) async {
    final usedScopes = scopes ?? this.scopes;

    Log.d('GoogleSignInMobileAdapter: starting sign-in with scopes: $usedScopes', tag: 'GoogleSignIn');

    try {
      // Ensure initialized
      await initialize();

      Log.d('GoogleSignInMobileAdapter: using direct authorization flow (single consent screen)', tag: 'GoogleSignIn');

      // Try to get existing account without UI
      final GoogleSignInAccount? existingAccount = _currentUser;

      if (existingAccount != null) {
        Log.d('GoogleSignInMobileAdapter: found existing account: ${existingAccount.email}', tag: 'GoogleSignIn');

        // Go directly to consent screen with existing account
        try {
          final authorization = await existingAccount.authorizationClient.authorizeScopes(usedScopes);
          Log.d('GoogleSignInMobileAdapter: consent completed successfully', tag: 'GoogleSignIn');
          return await _buildTokenMap(existingAccount, authorization, usedScopes);
        } catch (e) {
          Log.d(
            'GoogleSignInMobileAdapter: existing account consent failed, clearing and retrying: $e',
            tag: 'GoogleSignIn',
          );
          // Clear existing account and start fresh
          await _signIn.disconnect();
        }
      }

      // Create a temporary account just to get authorizationClient access
      // Use authenticate with scope hint - this will handle sign-in + consent in one flow
      Log.d('GoogleSignInMobileAdapter: authenticating with scope hint', tag: 'GoogleSignIn');

      final GoogleSignInAccount tempAccount = await _signIn.authenticate(scopeHint: usedScopes);

      Log.d(
        'GoogleSignInMobileAdapter: got account ${tempAccount.email}, proceeding to authorization',
        tag: 'GoogleSignIn',
      );

      // Go directly to consent screen for Drive scopes
      final authorization = await tempAccount.authorizationClient.authorizeScopes(usedScopes);
      Log.d('GoogleSignInMobileAdapter: authorization completed successfully', tag: 'GoogleSignIn');

      return await _buildTokenMap(tempAccount, authorization, usedScopes);
    } catch (e, st) {
      Log.e('GoogleSignInMobileAdapter: sign-in failed: $e', tag: 'GoogleSignIn', error: e, stack: st);

      final String help =
          '\nSoluciones sugeridas:'
          '\n- Verifica que google-services.json esté configurado correctamente'
          '\n- Asegúrate de que el SHA-1 certificate fingerprint esté registrado en Google Cloud Console'
          '\n- Confirma que los scopes solicitados estén habilitados para tu OAuth client'
          '\n- Si usas un clientId personalizado, verifica que sea del tipo correcto';

      throw StateError('Google Sign-In nativo falló: $e$help');
    }
  }

  /// Build token map from authorization
  Future<Map<String, dynamic>> _buildTokenMap(
    GoogleSignInAccount account,
    GoogleSignInClientAuthorization authorization,
    List<String> scopes,
  ) async {
    Log.d('GoogleSignInMobileAdapter: building token map for scopes: $scopes', tag: 'GoogleSignIn');

    try {
      // Get authorization headers (contains access token)
      final headers = await account.authorizationClient.authorizationHeaders(scopes);
      final accessToken = _extractAccessTokenFromHeaders(headers);

      // Get ID token if available (through older compatibility API)
      String? idToken;
      try {
        // This might not be available in newer versions, but try for compatibility
        final auth = account.authentication;
        idToken = auth.idToken;
      } catch (e) {
        Log.d('GoogleSignInMobileAdapter: could not get ID token: $e', tag: 'GoogleSignIn');
      }

      final Map<String, dynamic> tokenMap = {
        'access_token': accessToken,
        'token_type': 'Bearer',
        'expires_in': 3600, // Default expiration
        'scope': scopes.join(' '),
      };

      if (idToken != null) {
        tokenMap['id_token'] = idToken;
      }

      // Try to get server auth code for refresh token
      try {
        final serverAuth = await account.authorizationClient.authorizeServer(scopes);
        if (serverAuth != null) {
          final refreshTokens = await _exchangeServerAuthCode(serverAuth.serverAuthCode);
          if (refreshTokens['refresh_token'] != null) {
            tokenMap['refresh_token'] = refreshTokens['refresh_token'];
            tokenMap['access_token'] = refreshTokens['access_token'] ?? tokenMap['access_token'];
            if (refreshTokens['expires_in'] != null) {
              tokenMap['expires_in'] = refreshTokens['expires_in'];
            }
            Log.d('GoogleSignInMobileAdapter: successfully obtained refresh_token', tag: 'GoogleSignIn');
          }
        }
      } catch (e) {
        Log.w('GoogleSignInMobileAdapter: server auth code exchange failed: $e', tag: 'GoogleSignIn');
      }

      return tokenMap;
    } catch (e, st) {
      Log.e('GoogleSignInMobileAdapter: failed to build token map: $e', tag: 'GoogleSignIn', error: e, stack: st);
      rethrow;
    }
  }

  /// Extract access token from authorization headers
  String? _extractAccessTokenFromHeaders(Map<String, String>? headers) {
    if (headers == null) return null;

    final authHeader = headers['Authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7); // Remove 'Bearer ' prefix
    }

    return null;
  }

  /// Sign in silently without showing account chooser (if possible)
  Future<Map<String, dynamic>?> signInSilently({List<String>? scopes}) async {
    final usedScopes = scopes ?? this.scopes;

    Log.d('GoogleSignInMobileAdapter: attempting silent sign-in', tag: 'GoogleSignIn');

    try {
      // Ensure initialized
      await initialize();

      // Try lightweight authentication first
      await _signIn.attemptLightweightAuthentication();

      // Check if we have a current user
      final GoogleSignInAccount? account = _currentUser;
      if (account == null) {
        Log.d('GoogleSignInMobileAdapter: silent sign-in failed, no account available', tag: 'GoogleSignIn');
        return null;
      }

      Log.d('GoogleSignInMobileAdapter: silent sign-in successful as ${account.email}', tag: 'GoogleSignIn');

      // Check if we have authorization for the required scopes
      final GoogleSignInClientAuthorization? authorization = await account.authorizationClient.authorizationForScopes(
        usedScopes,
      );

      if (authorization == null) {
        Log.d('GoogleSignInMobileAdapter: no authorization for required scopes', tag: 'GoogleSignIn');
        return null;
      }

      return await _buildTokenMap(account, authorization, usedScopes);
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: silent sign-in failed: $e', tag: 'GoogleSignIn');
      return null;
    }
  }

  /// Exchange server auth code for refresh token
  Future<Map<String, dynamic>> _exchangeServerAuthCode(String serverAuthCode) async {
    final webClientId = Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
    final webClientSecret = Config.get('GOOGLE_CLIENT_SECRET_WEB', '').trim();

    if (webClientId.isEmpty) {
      throw StateError('GOOGLE_CLIENT_ID_WEB required for serverAuthCode exchange');
    }
    if (webClientSecret.isEmpty) {
      throw StateError('GOOGLE_CLIENT_SECRET_WEB required for serverAuthCode exchange');
    }

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': webClientId,
        'client_secret': webClientSecret,
        'code': serverAuthCode,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode == 200) {
      final tokens = jsonDecode(response.body) as Map<String, dynamic>;
      Log.d('GoogleSignInMobileAdapter: serverAuthCode exchange successful', tag: 'GoogleSignIn');
      return tokens;
    } else {
      final error = response.body;
      Log.w(
        'GoogleSignInMobileAdapter: serverAuthCode exchange failed: ${response.statusCode} $error',
        tag: 'GoogleSignIn',
      );
      throw HttpException('Token exchange failed: ${response.statusCode} $error');
    }
  }

  /// Sign out from Google Sign-In
  Future<void> signOut() async {
    try {
      await _signIn.disconnect();
      _currentUser = null;
      Log.d('GoogleSignInMobileAdapter: signed out successfully', tag: 'GoogleSignIn');
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: sign-out failed: $e', tag: 'GoogleSignIn');
      throw StateError('Sign-out failed: $e');
    }
  }

  /// Check if user is currently signed in
  Future<bool> isSignedIn() async {
    try {
      await initialize();
      return _currentUser != null;
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: isSignedIn check failed: $e', tag: 'GoogleSignIn');
      return false;
    }
  }

  /// Get current signed in account if available
  Future<GoogleSignInAccount?> getCurrentAccount() async {
    try {
      await initialize();
      return _currentUser;
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: getCurrentAccount failed: $e', tag: 'GoogleSignIn');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }
}
