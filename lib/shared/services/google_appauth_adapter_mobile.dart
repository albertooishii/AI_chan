import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Mobile adapter that uses the flutter_appauth plugin to perform a PKCE
/// authorization code flow on Android/iOS and exchange a code for tokens.
class GoogleAppAuthMobileAdapter {
  final List<String> scopes;
  final String clientId;
  final String? redirectUri;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  GoogleAppAuthMobileAdapter({
    required this.scopes,
    required this.clientId,
    this.redirectUri,
  });

  Future<Map<String, dynamic>> signIn({List<String>? scopes}) async {
    final usedScopes = (scopes ?? this.scopes);
    Log.d(
      'GoogleAppAuthMobileAdapter: starting authorizeAndExchangeCode clientId length=${clientId.length}',
      tag: 'GoogleAppAuthMobile',
    );

    // Determine redirect URI: prefer explicit parameter, then config, then sensible defaults
    String? redirect = redirectUri;
    try {
      final cfg = Config.get('GOOGLE_REDIRECT_URI', '').trim();
      if (cfg.isNotEmpty) redirect = cfg;
    } catch (_) {}
    try {
      if (redirect == null || redirect.isEmpty) {
        // Default custom scheme matching Android/iOS app manifest
        redirect = 'com.albertooishii.ai_chan:/oauthredirect';
      }
    } catch (_) {}

    const discovery =
        'https://accounts.google.com/.well-known/openid-configuration';
    Log.d(
      'GoogleAppAuthMobileAdapter: using discoveryUrl=$discovery redirect=$redirect clientIdLength=${clientId.length}',
      tag: 'GoogleAppAuthMobile',
    );

    final request = AuthorizationTokenRequest(
      clientId,
      redirect!,
      scopes: usedScopes,
      // Provide Google's discovery document so flutter_appauth can build
      // the correct authorization/token endpoints. This satisfies the
      // plugin's requirement that either issuer, discoveryUrl or
      // serviceConfiguration is provided.
      discoveryUrl: discovery,
      promptValues: ['consent'],
      // Request offline access so Google returns a refresh token
      additionalParameters: {'access_type': 'offline'},
    );

    try {
      final result = await _appAuth.authorizeAndExchangeCode(request);

      final map = <String, dynamic>{
        'access_token': result.accessToken,
        'id_token': result.idToken,
        'refresh_token': result.refreshToken,
        'expires_in': result.accessTokenExpirationDateTime
            ?.difference(DateTime.now())
            .inSeconds,
        'token_type': 'Bearer',
        'scope': usedScopes.join(' '),
      };

      // Use Firebase to sign in with obtained tokens to obtain a Firebase
      // refresh_token when available (keeps behavior aligned with desktop).
      try {
        final idToken = map['id_token'] as String?;
        final accessToken = map['access_token'] as String?;
        if (idToken != null || accessToken != null) {
          final credential = GoogleAuthProvider.credential(
            idToken: idToken,
            accessToken: accessToken,
          );
          final userCred = await FirebaseAuth.instance.signInWithCredential(
            credential,
          );
          final refreshToken = userCred.user?.refreshToken;
          if (refreshToken != null && refreshToken.isNotEmpty) {
            map['refresh_token'] = refreshToken;
          }
        }
      } catch (e) {
        Log.w(
          'GoogleAppAuthMobileAdapter: Firebase sign-in after AppAuth failed: $e',
          tag: 'GoogleAppAuthMobile',
        );
      }

      return map;
    } catch (e, st) {
      // Surface a clearer error for common Google "access blocked"/config issues.
      Log.e(
        'GoogleAppAuthMobileAdapter: AppAuth flow failed: $e',
        tag: 'GoogleAppAuthMobile',
        error: e,
        stack: st,
      );
      final msg = e.toString();
      String help =
          '\nHints: '
          '\n- Ensure the OAuth client ID in Config (GOOGLE_CLIENT_ID_ANDROID) matches the Android OAuth client in Google Cloud Console (package name + SHA-1).'
          '\n- Make sure the app\'s redirect URI (Config GOOGLE_REDIRECT_URI or default custom scheme) is registered and matches the intent-filter in AndroidManifest.'
          '\n- Verify the OAuth consent screen is configured and your account is allowed (add test users if the app is in testing).'
          '\n- If Google blocks browser-based OAuth for this client, consider using the Google Sign-In SDK or configure a web client correctly.';
      // Wrap assertion/PlatformException with actionable StateError
      throw StateError('AppAuth authorization failed: $msg$help');
    }
  }
}
