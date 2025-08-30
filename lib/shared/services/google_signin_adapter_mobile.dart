import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Native Google Sign-In adapter for Android/iOS with native account chooser
/// and proper refresh token handling
class GoogleSignInMobileAdapter {
  final List<String> scopes;
  final String? clientId;
  final bool useNativeChooser;
  GoogleSignIn? _googleSignIn;

  GoogleSignInMobileAdapter({
    required this.scopes,
    this.clientId,
    this.useNativeChooser = true, // Por defecto usar chooser nativo (bottom sheet)
  });

  GoogleSignIn get _signIn {
    if (_googleSignIn != null) return _googleSignIn!;

    // Configure GoogleSignIn with proper scopes and client ID
    if (Platform.isAndroid && useNativeChooser) {
      // Para Android: chooser nativo que se desliza desde abajo
      // NO usar serverClientId para obtener el chooser nativo que se desliza
      _googleSignIn = GoogleSignIn(
        scopes: scopes,
        forceCodeForRefreshToken: true,
        // Sin clientId específico para usar chooser nativo de Android
      );
      Log.d('GoogleSignInMobileAdapter: configured for native Android bottom-sheet chooser', tag: 'GoogleSignIn');
    } else {
      // Para iOS o chooser estándar: usar configuración estándar
      _googleSignIn = GoogleSignIn(scopes: scopes, clientId: _resolveClientId(), forceCodeForRefreshToken: true);
      Log.d('GoogleSignInMobileAdapter: configured for standard chooser', tag: 'GoogleSignIn');
    }

    return _googleSignIn!;
  }

  String? _resolveClientId() {
    if (clientId != null && clientId!.isNotEmpty) return clientId;

    try {
      if (Platform.isAndroid) {
        // Para Android con chooser estándar, usar el web client ID
        final webClientId = Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
        if (webClientId.isNotEmpty) {
          Log.d('GoogleSignInMobileAdapter: using web clientId for standard chooser', tag: 'GoogleSignIn');
          return webClientId;
        }
      } else if (Platform.isIOS) {
        final iosClientId = Config.get('GOOGLE_CLIENT_ID_IOS', '').trim();
        if (iosClientId.isNotEmpty) return iosClientId;
      }
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: error resolving clientId: $e', tag: 'GoogleSignIn');
    }

    return null;
  }

  /// Sign in with native Google Sign-In chooser and obtain tokens including refresh_token
  Future<Map<String, dynamic>> signIn({List<String>? scopes, bool forceAccountChooser = true}) async {
    final usedScopes = scopes ?? this.scopes;

    Log.d('GoogleSignInMobileAdapter: starting native sign-in with scopes: $usedScopes', tag: 'GoogleSignIn');

    try {
      // Only sign out if we want to force account chooser
      if (forceAccountChooser) {
        await _signIn.signOut();
        Log.d('GoogleSignInMobileAdapter: signed out to force account chooser', tag: 'GoogleSignIn');
      }

      // Sign in with account chooser (or silently if already signed in)
      final GoogleSignInAccount? account = await _signIn.signIn();
      if (account == null) {
        throw StateError('User cancelled sign-in');
      }

      Log.d(
        'GoogleSignInMobileAdapter: signed in as ${account.email}',
        tag: 'GoogleSignIn',
      ); // Get authentication tokens
      final GoogleSignInAuthentication auth = await account.authentication;

      // Get server auth code for refresh token
      final String? serverAuthCode = account.serverAuthCode;

      Log.d(
        'GoogleSignInMobileAdapter: obtained tokens - accessToken: ${auth.accessToken != null}, '
        'idToken: ${auth.idToken != null}, serverAuthCode: ${serverAuthCode != null}',
        tag: 'GoogleSignIn',
      );

      Map<String, dynamic> tokenMap = {
        'access_token': auth.accessToken,
        'id_token': auth.idToken,
        'token_type': 'Bearer',
        'expires_in': 3600, // Default expiration
        'scope': usedScopes.join(' '),
      };

      // Exchange serverAuthCode for refresh token if available
      // Note: Con chooser nativo, el serverAuthCode puede no estar disponible
      // pero seguiremos teniendo access token válido
      if (serverAuthCode != null && serverAuthCode.isNotEmpty) {
        try {
          final refreshTokens = await _exchangeServerAuthCode(serverAuthCode);
          if (refreshTokens['refresh_token'] != null) {
            tokenMap['refresh_token'] = refreshTokens['refresh_token'];
            tokenMap['access_token'] = refreshTokens['access_token'] ?? tokenMap['access_token'];
            if (refreshTokens['expires_in'] != null) {
              tokenMap['expires_in'] = refreshTokens['expires_in'];
            }
          }
        } catch (e) {
          Log.d(
            'GoogleSignInMobileAdapter: serverAuthCode exchange failed (expected with native chooser): $e',
            tag: 'GoogleSignIn',
          );
          // Continue without refresh token - we still have access token
        }
      } else {
        Log.d(
          'GoogleSignInMobileAdapter: no serverAuthCode available with native chooser, using access token only',
          tag: 'GoogleSignIn',
        );
      }

      // Also sign in with Firebase to maintain consistency
      try {
        if (auth.idToken != null || auth.accessToken != null) {
          final credential = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
          final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
          final firebaseRefreshToken = userCred.user?.refreshToken;
          if (firebaseRefreshToken != null && firebaseRefreshToken.isNotEmpty) {
            // Prefer OAuth refresh token over Firebase refresh token for Drive API
            tokenMap['firebase_refresh_token'] = firebaseRefreshToken;
          }
        }
      } catch (e) {
        Log.w('GoogleSignInMobileAdapter: Firebase sign-in failed: $e', tag: 'GoogleSignIn');
      }

      return tokenMap;
    } catch (e, st) {
      Log.e('GoogleSignInMobileAdapter: sign-in failed: $e', tag: 'GoogleSignIn', error: e, stack: st);

      String help =
          '\nSoluciones sugeridas:'
          '\n- Verifica que google-services.json esté configurado correctamente'
          '\n- Asegúrate de que el SHA-1 certificate fingerprint esté registrado en Google Cloud Console'
          '\n- Confirma que los scopes solicitados estén habilitados para tu OAuth client'
          '\n- Si usas un clientId personalizado, verifica que sea del tipo correcto (Web para serverAuthCode)';

      throw StateError('Google Sign-In nativo falló: $e$help');
    }
  }

  /// Sign in silently without showing account chooser (if possible)
  Future<Map<String, dynamic>?> signInSilently({List<String>? scopes}) async {
    final usedScopes = scopes ?? this.scopes;

    Log.d('GoogleSignInMobileAdapter: attempting silent sign-in', tag: 'GoogleSignIn');

    try {
      // Try silent sign-in first (no account chooser)
      final GoogleSignInAccount? account = await _signIn.signInSilently();
      if (account == null) {
        Log.d('GoogleSignInMobileAdapter: silent sign-in failed, no account available', tag: 'GoogleSignIn');
        return null;
      }

      Log.d('GoogleSignInMobileAdapter: silent sign-in successful as ${account.email}', tag: 'GoogleSignIn');

      // Get authentication tokens
      final GoogleSignInAuthentication auth = await account.authentication;
      final String? serverAuthCode = account.serverAuthCode;

      Map<String, dynamic> tokenMap = {
        'access_token': auth.accessToken,
        'id_token': auth.idToken,
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': usedScopes.join(' '),
      };

      // Exchange serverAuthCode for refresh token if available
      if (serverAuthCode != null && serverAuthCode.isNotEmpty) {
        try {
          final refreshTokens = await _exchangeServerAuthCode(serverAuthCode);
          if (refreshTokens['refresh_token'] != null) {
            tokenMap['refresh_token'] = refreshTokens['refresh_token'];
            tokenMap['access_token'] = refreshTokens['access_token'] ?? tokenMap['access_token'];
            if (refreshTokens['expires_in'] != null) {
              tokenMap['expires_in'] = refreshTokens['expires_in'];
            }
          }
        } catch (e) {
          Log.w('GoogleSignInMobileAdapter: silent serverAuthCode exchange failed: $e', tag: 'GoogleSignIn');
        }
      }

      return tokenMap;
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
      await _signIn.signOut();
      Log.d('GoogleSignInMobileAdapter: signed out successfully', tag: 'GoogleSignIn');
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: sign-out failed: $e', tag: 'GoogleSignIn');
      throw StateError('Sign-out failed: $e');
    }
  }

  /// Check if user is currently signed in
  Future<bool> isSignedIn() async {
    try {
      return await _signIn.isSignedIn();
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: isSignedIn check failed: $e', tag: 'GoogleSignIn');
      return false;
    }
  }

  /// Get current signed in account if available
  Future<GoogleSignInAccount?> getCurrentAccount() async {
    try {
      return await _signIn.signInSilently();
    } catch (e) {
      Log.w('GoogleSignInMobileAdapter: getCurrentAccount failed: $e', tag: 'GoogleSignIn');
      return null;
    }
  }
}
