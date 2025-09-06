import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';

/// AppAuth adapter for desktop platforms using PKCE authorization-code flow
class GoogleAppAuthAdapter {
  GoogleAppAuthAdapter({
    required this.scopes,
    required this.clientId,
    this.redirectUri,
  });
  final List<String> scopes;
  final String clientId;
  final String? redirectUri;

  static String? lastAuthUrl;

  /// Open URL in system browser
  static Future<void> openBrowser(final String url) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', url]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else {
        await Process.start('xdg-open', [url]);
      }
      Log.d('GoogleAppAuthAdapter: opened browser', tag: 'GoogleAppAuth');
    } on Exception catch (e) {
      Log.w(
        'GoogleAppAuthAdapter: failed to open browser: $e',
        tag: 'GoogleAppAuth',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> signIn({final List<String>? scopes}) async {
    final usedScopes = (scopes ?? this.scopes).join(' ');

    String? redirect = redirectUri;
    if (redirect == null || redirect.isEmpty) {
      try {
        redirect = Config.get('GOOGLE_REDIRECT_URI', '').trim();
      } on Exception catch (_) {}
    }

    HttpServer? server;
    Uri authRedirect;

    if (redirect == null || redirect.isEmpty) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      redirect = 'http://127.0.0.1:${server.port}/';
      Log.d(
        'GoogleAppAuthAdapter: bound loopback on port ${server.port}',
        tag: 'GoogleAppAuth',
      );
    }

    authRedirect = Uri.parse(redirect);

    final codeVerifier = _createCodeVerifier();
    final codeChallenge = _codeChallenge(codeVerifier);
    final state = _randomString(16);

    final authorizationEndpoint =
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': clientId,
            'redirect_uri': authRedirect.toString(),
            'scope': usedScopes,
            'state': state,
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
            'access_type': 'offline',
            'prompt': 'consent',
          },
        );

    GoogleAppAuthAdapter.lastAuthUrl = authorizationEndpoint.toString();

    try {
      await GoogleAppAuthAdapter.openBrowser(authorizationEndpoint.toString());
    } on Exception catch (e) {
      Log.w(
        'GoogleAppAuthAdapter: failed to open browser: $e',
        tag: 'GoogleAppAuth',
      );
    }

    String? code;
    String? returnedState;

    try {
      if (server != null) {
        final req = await server.first.timeout(const Duration(minutes: 5));
        final params = req.uri.queryParameters;
        code = params['code'];
        returnedState = params['state'];

        try {
          final page = await rootBundle.loadString('assets/oauth_success.html');
          final appName = Config.get('APP_NAME', '').toString();
          final replaced = page.replaceAll(
            '%APP_NAME%',
            appName.isNotEmpty ? appName : 'AI Chan',
          );

          req.response.statusCode = 200;
          req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
          req.response.write(replaced);
          await req.response.close();
        } on Exception {
          req.response.statusCode = 200;
          req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
          req.response.write(
            '<html><body><h3>Autenticación completada. Puedes cerrar esta ventana.</h3></body></html>',
          );
          await req.response.close();
        }
      } else {
        throw StateError('No loopback server available');
      }
    } on Exception catch (e, st) {
      Log.e(
        'GoogleAppAuthAdapter: AppAuth failed: $e',
        tag: 'GoogleAppAuth',
        error: e,
        stack: st,
      );
      await _closeServer(server);
      throw StateError('Authentication failed: $e');
    }

    if (returnedState != state) {
      await _closeServer(server);
      throw StateError('State mismatch in response');
    }

    if (code == null || code.isEmpty) {
      await _closeServer(server);
      throw StateError('No authorization code returned');
    }

    try {
      String? clientSecret;
      try {
        clientSecret = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '').trim();
        if (clientSecret.isEmpty) {
          clientSecret = Config.get('GOOGLE_CLIENT_SECRET_WEB', '').trim();
        }
        if (clientSecret.isEmpty) clientSecret = null;
      } on Exception catch (_) {
        clientSecret = null;
      }

      final tokenUrl = Uri.parse('https://oauth2.googleapis.com/token');
      final body = {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'redirect_uri': authRedirect.toString(),
        'code_verifier': codeVerifier,
      };

      if (clientSecret != null && clientSecret.isNotEmpty) {
        body['client_secret'] = clientSecret;
      }

      final tokenRes = await http.post(
        tokenUrl,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
        throw StateError(
          'Token exchange failed: ${tokenRes.statusCode} ${tokenRes.body}',
        );
      }

      final map = Map<String, dynamic>.of(jsonDecode(tokenRes.body));

      await _closeServer(server);

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
      } on Exception catch (_) {}

      return map;
    } on Exception catch (e, st) {
      Log.e(
        'GoogleAppAuthAdapter: token exchange error: $e',
        tag: 'GoogleAppAuth',
        error: e,
        stack: st,
      );
      await _closeServer(server);
      throw StateError('Token exchange failed: $e');
    }
  }

  Future<void> _closeServer(final HttpServer? server) async {
    try {
      if (server != null) {
        await server.close(force: true);
      }
    } on Exception catch (_) {}
  }

  static String _createCodeVerifier([final int length = 64]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(final String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String _randomString(final int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
